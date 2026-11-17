"""A small reader for ESRI Shapefiles and their dBASE attribute tables.

Two files the Japanese build reads come as Shapefiles: the Ministry of the Environment's
national park zones (``nps.zip``) and Natural Earth's admin-1 layer. Both are polygons in
geographic coordinates, so this reads polygons (with or without Z and M) and the ``.dbf``
beside them, straight out of the zip, and nothing else. No GDAL: the pipeline keeps to
pure Python and numpy.

The attribute encoding is the part that goes wrong. A ``.cpg`` file names it where there
is one (Natural Earth's says UTF-8); otherwise the dBASE header's language driver byte
does, and a Japanese government file without either is Shift_JIS — read here as CP932,
Microsoft's superset of it, which is what Japanese GIS software writes.
"""

from __future__ import annotations

import struct
import zipfile
from collections.abc import Iterator
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from ... import outline

# Polygon, PolygonZ, PolygonM: the same layout up to the points.
_POLYGON_TYPES = frozenset({5, 15, 25})

# dBASE language driver IDs worth knowing here. 0x13 is "Japanese Shift-JIS" in the
# ArcGIS table; 0x7B and 0x4D appear in files written by other Japanese tools.
_DRIVER_ENCODINGS = {0x13: "cp932", 0x7B: "cp932", 0x4D: "cp932", 0x57: None}


# The key a deleted dBASE record carries instead of its attributes.
DELETED = "_deleted"


class ShapefileError(ValueError):
    """A file that is not the Shapefile this reader expected."""


@dataclass(frozen=True)
class Feature:
    """One record: its attributes and its polygons as ``outline`` rings (lon, lat)."""

    attributes: dict[str, Any]
    polygons: list[outline.Polygon]


# MARK: - Geometry


def read_polygons(data: bytes) -> Iterator[list[outline.Polygon] | None]:
    """Each record's polygons, in file order; ``None`` for a null shape."""
    if len(data) < 100 or struct.unpack_from(">i", data, 0)[0] != 9994:
        raise ShapefileError("not a Shapefile: the header's file code is not 9994")
    shape_type = struct.unpack_from("<i", data, 32)[0]
    if shape_type not in _POLYGON_TYPES and shape_type != 0:
        raise ShapefileError(f"shape type {shape_type} is not a polygon")
    offset = 100
    while offset + 8 <= len(data):
        content_words = struct.unpack_from(">i", data, offset + 4)[0]
        start = offset + 8
        offset = start + content_words * 2
        record_type = struct.unpack_from("<i", data, start)[0]
        if record_type == 0:
            yield None
            continue
        if record_type not in _POLYGON_TYPES:
            raise ShapefileError(f"record of shape type {record_type} in a polygon file")
        parts_count, points_count = struct.unpack_from("<2i", data, start + 36)
        parts = list(struct.unpack_from(f"<{parts_count}i", data, start + 44))
        points_at = start + 44 + 4 * parts_count
        values = struct.unpack_from(f"<{points_count * 2}d", data, points_at)
        rings: list[outline.Ring] = []
        for index, first in enumerate(parts):
            last = parts[index + 1] if index + 1 < parts_count else points_count
            ring = [(values[2 * i], values[2 * i + 1]) for i in range(first, last)]
            if len(ring) > 1 and ring[0] == ring[-1]:
                ring.pop()
            if len(ring) >= 3:
                rings.append(ring)
        yield group_rings(rings)


def signed_area(ring: outline.Ring) -> float:
    """Shoelace area: positive counter-clockwise, negative clockwise."""
    total = 0.0
    for (x1, y1), (x2, y2) in zip(ring, ring[1:] + ring[:1], strict=True):
        total += x1 * y2 - x2 * y1
    return total / 2


def group_rings(rings: list[outline.Ring]) -> list[outline.Polygon]:
    """Rings into polygons. The Shapefile convention is outer rings clockwise and holes
    counter-clockwise, in no promised order: each hole goes to the smallest outer ring that
    holds it, and a hole no outer ring holds is kept as an outer ring of its own rather
    than lost."""
    outers: list[outline.Ring] = []
    holes: list[outline.Ring] = []
    for ring in rings:
        (outers if signed_area(ring) <= 0 else holes).append(ring)
    polygons: list[outline.Polygon] = [[ring] for ring in outers]
    areas = [abs(signed_area(ring)) for ring in outers]
    for hole in holes:
        lon, lat = hole[0]
        home = None
        for index, polygon in enumerate(polygons):
            if outline.contains([[polygon[0]]], lon, lat) and (
                home is None or areas[index] < areas[home]
            ):
                home = index
        if home is None:
            polygons.append([hole])
            areas.append(abs(signed_area(hole)))
        else:
            polygons[home].append(hole)
    return polygons


# MARK: - Attributes


def read_dbf(data: bytes, encoding: str | None = None) -> Iterator[dict[str, Any]]:
    """Each record's attributes, in file order. A deleted record is ``{DELETED: True}``,
    so the rows stay aligned with the shapes; ``read_zip`` drops it.

    Character fields are decoded with ``encoding``, else the one the header's language
    driver names, else UTF-8 falling back to CP932 field by field. Numbers come back as
    ``int`` or ``float``, and an empty number as ``None``.
    """
    if len(data) < 32:
        raise ShapefileError("not a dBASE file: shorter than its header")
    count = struct.unpack_from("<I", data, 4)[0]
    header_length, record_length = struct.unpack_from("<HH", data, 8)
    if encoding is None:
        encoding = _DRIVER_ENCODINGS.get(data[29])
    fields: list[tuple[str, str, int, int]] = []
    position = 32
    while position < header_length - 1 and data[position] != 0x0D:
        raw_name = data[position : position + 11].split(b"\x00", 1)[0]
        name = raw_name.decode("ascii", "replace").strip()
        kind = chr(data[position + 11])
        length, decimals = data[position + 16], data[position + 17]
        fields.append((name, kind, length, decimals))
        position += 32
    for index in range(count):
        start = header_length + index * record_length
        record = data[start : start + record_length]
        if not record or record[:1] == b"*":
            # Kept as a marker so the table stays aligned with the shapes.
            yield {DELETED: True}
            continue
        attributes: dict[str, Any] = {}
        cursor = 1
        for name, kind, length, decimals in fields:
            raw = record[cursor : cursor + length]
            cursor += length
            attributes[name] = _field_value(raw, kind, decimals, encoding)
        yield attributes


def _field_value(raw: bytes, kind: str, decimals: int, encoding: str | None) -> Any:
    if kind in ("N", "F"):
        text = raw.decode("ascii", "replace").strip().replace("\x00", "")
        if not text or text.startswith("*"):
            return None
        try:
            return float(text) if decimals or "." in text or "e" in text.lower() else int(text)
        except ValueError:
            return None
    if kind == "L":
        return {"T": True, "Y": True, "F": False, "N": False}.get(
            raw.decode("ascii", "replace").strip().upper()
        )
    text_bytes = raw.rstrip(b" \x00")
    if encoding:
        return text_bytes.decode(encoding, "replace").strip()
    try:
        return text_bytes.decode("utf-8").strip()
    except UnicodeDecodeError:
        return text_bytes.decode("cp932", "replace").strip()


# MARK: - Zips


def read_zip(path: Path, stem: str | None = None) -> list[Feature]:
    """Every feature of the Shapefile in a zip: the one named ``stem`` (without its
    extension, in any folder of the zip), or the only one there is."""
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        shps = [name for name in names if name.lower().endswith(".shp")]
        if stem is not None:
            shps = [name for name in shps if Path(name).stem == stem]
        if len(shps) != 1:
            raise ShapefileError(f"{path.name}: expected one Shapefile, found {shps}")
        base = shps[0][:-4]

        def member(extension: str) -> bytes | None:
            for name in names:
                if name[:-4] == base and name[-4:].lower() == extension:
                    return archive.read(name)
            return None

        shp, dbf, cpg = member(".shp"), member(".dbf"), member(".cpg")
    if shp is None or dbf is None:
        raise ShapefileError(f"{path.name}: {base} lacks its .shp or .dbf")
    encoding = _cpg_encoding(cpg)
    geometries = list(read_polygons(shp))
    rows = list(read_dbf(dbf, encoding))
    if len(rows) != len(geometries):
        raise ShapefileError(
            f"{path.name}: {len(geometries)} shapes but {len(rows)} attribute rows"
        )
    return [
        Feature(attributes=row, polygons=polygons or [])
        for row, polygons in zip(rows, geometries, strict=True)
        if not row.get(DELETED)
    ]


def _cpg_encoding(cpg: bytes | None) -> str | None:
    if not cpg:
        return None
    name = cpg.decode("ascii", "replace").strip().lower()
    aliases = {"utf-8": "utf-8", "utf8": "utf-8", "65001": "utf-8", "shift_jis": "cp932",
               "sjis": "cp932", "932": "cp932", "cp932": "cp932"}
    return aliases.get(name, name or None)
