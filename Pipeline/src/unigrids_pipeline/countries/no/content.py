"""Norway's curated half: ``content/countries/no/``.

The park list fixes each national park's permanent identifier and keys it to
Naturvernområder; each guide (``guides/<id>.json``, the format in
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

DIRECTORY = config.CONTENT_DIR / "countries" / "no"
GUIDES_DIR = DIRECTORY / "guides"
THEMES_PATH = config.CONTENT_DIR / "themes.json"


@cache
def parks() -> list[dict[str, Any]]:
    """The 48 national parks: ``id``, ``name``, ``naturvernId``, ``svalbard``."""
    return json.loads((DIRECTORY / "national-parks.json").read_text())["parks"]


def park_slug(place_id: str) -> str:
    """``no-np-jotunheimen`` → ``jotunheimen``: the stem a park's sights are named under."""
    return place_id.removeprefix("no-np-")


def guide(place_id: str, *, directory: Path | None = None) -> dict[str, Any] | None:
    path = (directory or GUIDES_DIR) / f"{place_id}.json"
    if not path.exists():
        return None
    # Read once per saved version: the fetch and the build both ask several times.
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
    """``"File:Besseggen.jpg"`` → ``"Besseggen.jpg"``, with underscores as spaces, the
    form Commons titles use."""
    if not isinstance(file, str):
        return None
    name = file.strip()
    for prefix in ("File:", "file:", "Fil:", "Image:"):
        name = name.removeprefix(prefix)
    name = name.replace("_", " ").strip()
    return name or None


def first_source_url(place_id: str) -> str | None:
    """The guide's first source on norgesnasjonalparker.no: the park's own page."""
    for source in (guide(place_id) or {}).get("sources") or []:
        url = (source or {}).get("url") or ""
        if "norgesnasjonalparker.no" in url:
            return url
    return None


@cache
def theme_ids() -> frozenset[str]:
    return frozenset(theme["id"] for theme in json.loads(THEMES_PATH.read_text())["themes"])
