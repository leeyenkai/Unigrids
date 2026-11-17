"""Australia's curated half: ``content/countries/au/``.

The park list fixes each national park's permanent identifier, keys it to its CAPAD
records (``capadName``, ``capadAlsoNames`` and ``state``) and gives its name, managing
agency and passport region; each guide (``guides/<id>.json``, the format in
``content/countries/README.md``) carries the prose, facts, sights and photographs Unigrids
chose. Guides are written by hand and may be missing or half-saved while someone works on
them, so a guide that is absent or does not parse is reported and treated as absent.
"""

from __future__ import annotations

import json
from functools import cache
from pathlib import Path
from typing import Any

from ... import config

DIRECTORY = config.CONTENT_DIR / "countries" / "au"
GUIDES_DIR = DIRECTORY / "guides"


@cache
def parks() -> list[dict[str, Any]]:
    """The 51 national parks with a guide: ``id``, ``name``, ``state``, ``agency``,
    ``capadName``, ``passportRegion`` and, where they apply, ``capadAlsoNames``,
    ``localName`` and ``jointlyManaged``."""
    return json.loads((DIRECTORY / "national-parks.json").read_text())["parks"]


def capad_names(park: dict[str, Any]) -> list[str]:
    """Every CAPAD ``NAME`` that is the park: its own and those it lists as the same."""
    return [park["capadName"], *(park.get("capadAlsoNames") or [])]


def park_slug(place_id: str) -> str:
    """``au-np-kakadu`` → ``kakadu``: the stem a park's sights are named under."""
    return place_id.removeprefix("au-np-")


def guide(place_id: str, *, directory: Path | None = None) -> dict[str, Any] | None:
    path = (directory or GUIDES_DIR) / f"{place_id}.json"
    if not path.exists():
        return None
    return _read_guide(path, path.stat().st_mtime_ns)


@cache
def _read_guide(path: Path, _version: int) -> dict[str, Any] | None:
    try:
        payload = json.loads(path.read_text())
    except (json.JSONDecodeError, UnicodeDecodeError) as error:
        print(f"    {path.stem}: guide does not parse ({error}); built without it")
        return None
    if not isinstance(payload, dict):
        print(f"    {path.stem}: guide is not an object; built without it")
        return None
    return payload


def guide_photos(place_id: str) -> list[dict[str, Any]]:
    """The guide's photographs, hero first: ``{"file": "File:…", "caption", "altText"}``."""
    return [
        photo
        for photo in (guide(place_id) or {}).get("photos") or []
        if isinstance(photo, dict) and commons_name(photo.get("file"))
    ]


def commons_name(file: Any) -> str | None:
    """``"File:Twelve Apostles.jpg"`` → ``"Twelve Apostles.jpg"``, with underscores as
    spaces, the form Commons titles use."""
    if not isinstance(file, str):
        return None
    name = file.strip()
    for prefix in ("File:", "file:", "Image:"):
        name = name.removeprefix(prefix)
    name = name.replace("_", " ").strip()
    return name or None
