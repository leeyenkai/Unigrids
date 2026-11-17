"""The pictures passport stamps carry (SPECIFICATION.md §9): each national park's own
drawing, and shared motifs for every other kind of place.

Each picture is an SVG file in ``content/emblems/``, drawn for Unigrids as original line
art in one ink on a 100 × 60 canvas: ``<path d="…"/>`` for a line, ``<path class="fill"
d="…"/>`` for a solid area, and the subject in a ``data-subject`` attribute for VoiceOver.
A national park's file is named for its ID (``np-yosemite.svg``); a motif's for its key
(``motif-lighthouse.svg``). Nothing here draws: the build checks the files and copies
their geometry into ``emblems.json``, and names each park's own picture on its record.
"""

from __future__ import annotations

import re
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any

from . import config

DIR = config.CONTENT_DIR / "emblems"
WIDTH, HEIGHT = 100, 60
# The commands the app's reader understands (`SVGPathParser`): no arcs.
_ALLOWED = re.compile(r"^[MmLlHhVvCcSsQqTtZz0-9eE.,+\-\s]+$")
_SVG = "{http://www.w3.org/2000/svg}"


class EmblemError(ValueError):
    """A drawing the app could not draw as authored."""


def read(path: Path) -> dict[str, Any]:
    """One drawing's subject, canvas and parts, checked."""
    root = ET.parse(path).getroot()
    view_box = [float(value) for value in (root.get("viewBox") or "").split()]
    if view_box != [0, 0, WIDTH, HEIGHT]:
        raise EmblemError(f"{path.name}: viewBox must be 0 0 {WIDTH} {HEIGHT}")
    subject = (root.get("data-subject") or "").strip()
    if not subject:
        raise EmblemError(f"{path.name}: no data-subject")
    parts = []
    for element in root.iter():
        if element.tag not in (f"{_SVG}path", "path"):
            continue
        data = " ".join((element.get("d") or "").split())
        if not data or not _ALLOWED.match(data):
            raise EmblemError(f"{path.name}: a path the app cannot read: {data[:40]}")
        parts.append({"d": data, "fill": "fill" in (element.get("class") or "").split()})
    if not parts:
        raise EmblemError(f"{path.name}: nothing drawn")
    return {"subject": subject, "width": WIDTH, "height": HEIGHT, "parts": parts}


def load(directory: Path = DIR) -> dict[str, dict[str, Any]]:
    """Every drawing, by key."""
    if not directory.is_dir():
        return {}
    return {path.stem: read(path) for path in sorted(directory.glob("*.svg"))}


def attach(places: list[dict[str, Any]], drawn: dict[str, Any]) -> list[str]:
    """Name each place's own drawing on its record. Returns the national parks that have
    none yet, which stamp with their kind's motif until one is drawn."""
    missing = []
    for place in places:
        if place["id"] in drawn:
            place["emblem"] = place["id"]
        elif place.get("kind") == "nationalPark":
            missing.append(place["id"])
    return missing
