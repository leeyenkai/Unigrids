"""Just enough of an Excel workbook reader for the Ministry's statistics tables.

An ``.xlsx`` file is a zip of XML parts. This reads the shared strings and one worksheet's
cell values with the standard library — no openpyxl — and hands back a grid. Formulas
are read by their cached value, which is what Excel last computed and saved; styles,
merged cells and comments are ignored.
"""

from __future__ import annotations

import re
import zipfile
from io import BytesIO
from pathlib import Path
from xml.etree import ElementTree

_MAIN = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
_RELATIONSHIPS = "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}"
_PACKAGE_RELATIONSHIPS = "{http://schemas.openxmlformats.org/package/2006/relationships}"
_REFERENCE = re.compile(r"^([A-Z]+)(\d+)$")

Cell = str | float | None
Grid = dict[int, dict[int, Cell]]
"""Row number (1-based) → column number (1-based) → value."""


def column_number(letters: str) -> int:
    """``A`` → 1, ``Z`` → 26, ``AA`` → 27."""
    number = 0
    for letter in letters:
        number = number * 26 + ord(letter) - ord("A") + 1
    return number


def sheet_names(source: Path | bytes) -> list[str]:
    with _open(source) as archive:
        workbook = ElementTree.fromstring(archive.read("xl/workbook.xml"))
    return [sheet.get("name") or "" for sheet in workbook.iter(f"{_MAIN}sheet")]


def read_sheet(source: Path | bytes, sheet: int | str = 0) -> Grid:
    """One worksheet's values, by position or by name."""
    with _open(source) as archive:
        strings = _shared_strings(archive)
        path = _sheet_path(archive, sheet)
        root = ElementTree.fromstring(archive.read(path))
    grid: Grid = {}
    for cell in root.iter(f"{_MAIN}c"):
        match = _REFERENCE.match(cell.get("r") or "")
        if not match:
            continue
        value = _cell_value(cell, strings)
        if value is None or value == "":
            continue
        row, column = int(match.group(2)), column_number(match.group(1))
        grid.setdefault(row, {})[column] = value
    return grid


def _open(source: Path | bytes) -> zipfile.ZipFile:
    return zipfile.ZipFile(BytesIO(source) if isinstance(source, bytes) else source)


def _shared_strings(archive: zipfile.ZipFile) -> list[str]:
    try:
        root = ElementTree.fromstring(archive.read("xl/sharedStrings.xml"))
    except KeyError:
        return []
    # A string with rich-text runs keeps its text in several <t> elements; phonetic
    # guides (<rPh>, the furigana Japanese files carry) are not part of the text.
    strings = []
    for item in root.iter(f"{_MAIN}si"):
        parts = [
            text.text or ""
            for child in item
            if child.tag in (f"{_MAIN}t", f"{_MAIN}r")
            for text in ([child] if child.tag == f"{_MAIN}t" else child.iter(f"{_MAIN}t"))
        ]
        strings.append("".join(parts))
    return strings


def _sheet_path(archive: zipfile.ZipFile, sheet: int | str) -> str:
    workbook = ElementTree.fromstring(archive.read("xl/workbook.xml"))
    sheets = list(workbook.iter(f"{_MAIN}sheet"))
    if isinstance(sheet, int):
        chosen = sheets[sheet]
    else:
        chosen = next(entry for entry in sheets if entry.get("name") == sheet)
    relationship = chosen.get(f"{_RELATIONSHIPS}id")
    relationships = ElementTree.fromstring(archive.read("xl/_rels/workbook.xml.rels"))
    for entry in relationships.iter(f"{_PACKAGE_RELATIONSHIPS}Relationship"):
        if entry.get("Id") == relationship:
            target = entry.get("Target") or ""
            return target.lstrip("/") if target.startswith("/") else f"xl/{target}"
    raise KeyError(f"no worksheet part for sheet {sheet!r}")


def _cell_value(cell: ElementTree.Element, strings: list[str]) -> Cell:
    kind = cell.get("t")
    if kind == "inlineStr":
        return "".join(text.text or "" for text in cell.iter(f"{_MAIN}t"))
    raw = cell.find(f"{_MAIN}v")
    if raw is None or raw.text is None:
        return None
    if kind == "s":
        index = int(raw.text)
        return strings[index] if 0 <= index < len(strings) else None
    if kind in ("str", "e"):
        return raw.text if kind == "str" else None
    if kind == "b":
        return float(raw.text)
    try:
        return float(raw.text)
    except ValueError:
        return raw.text
