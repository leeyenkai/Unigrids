"""Japan's curated content: ``content/countries/jp/``.

The park list is the one file that must exist. Guides are written park by park, so a
missing guide — or one a writer has not finished saving — leaves its park with what the
sources give, and the build says so, rather than failing.
"""

from __future__ import annotations

import json
from functools import cache
from typing import Any

from ... import config

DIRECTORY = config.CONTENT_DIR / "countries" / "jp"
GUIDES_DIRECTORY = DIRECTORY / "guides"


@cache
def national_parks() -> list[dict[str, Any]]:
    """The 35 national parks: ``id``, ``name``, ``slug``, ``localName``,
    ``passportRegion``."""
    return json.loads((DIRECTORY / "national-parks.json").read_text())["parks"]


def short_name(park: dict[str, Any]) -> str:
    """The name the Ministry's data files use: ``知床国立公園`` → ``知床``."""
    return str(park["localName"]).removesuffix("国立公園")


def slug(place_id: str) -> str:
    """``jp-np-shiretoko`` → ``shiretoko``: the stem of a park's sight identifiers."""
    return place_id.removeprefix("jp-np-")


def guide(place_id: str) -> dict[str, Any] | None:
    """A park's guide, or ``None`` when there is none yet or it does not read as JSON."""
    path = GUIDES_DIRECTORY / f"{place_id}.json"
    if not path.exists():
        return None
    try:
        payload = json.loads(path.read_text())
    except (json.JSONDecodeError, UnicodeDecodeError) as error:
        print(f"    content: {path.name} is not valid JSON yet ({error}); left out")
        return None
    return payload if isinstance(payload, dict) else None
