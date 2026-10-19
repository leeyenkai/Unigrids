"""The curated, version-controlled half of the reference dataset (``content/``).

Fetched data says what a source published; these files say what Unigrids chose to do with
it — which state parks and federal sites the map carries, which sights a guide ranks, and
every sentence of guide prose. They are prose and judgement, so they live under version
control as files rather than being regenerated (``SPECIFICATION.md`` §12, step 4).

Also here: the photograph policy, because choosing a photo is a curation decision with a
licensing consequence, and the fetch and the build must agree on it exactly.
"""

from __future__ import annotations

import json
import re
from functools import cache
from pathlib import Path
from typing import Any

from . import config

GUIDES_DIR = config.CONTENT_DIR / "guides"

# A photograph is reused only when the NPS is credited for it (SPECIFICATION.md §15).
# The API's credits are free text, so the rule is a pattern: credited to the NPS, and
# nothing in the credit suggesting somebody else holds rights in it.
_NPS_CREDIT = re.compile(r"^\s*(nps|national park service)\b", re.IGNORECASE)
_THIRD_PARTY = re.compile(
    r"©|\(c\)|copyright|courtesy|permission|volunteer|\bvip\b|licen[cs]ed|getty|shutterstock",
    re.IGNORECASE,
)

# How many photographs a national park's guide carries: one hero and a short gallery.
PHOTOS_PER_PARK = 5


def is_public_domain_credit(credit: str | None) -> bool:
    """Whether an NPS API photo credit reads as an NPS work, and so public domain."""
    if not credit:
        return False
    return bool(_NPS_CREDIT.search(credit)) and not _THIRD_PARTY.search(credit)


def choose_photos(
    images: list[dict[str, Any]],
    limit: int = PHOTOS_PER_PARK,
    keywords: list[str] | None = None,
) -> list[dict]:
    """The photographs a park's guide uses, in the NPS's own order, NPS-credited only.

    ``keywords`` narrows a shared photo set to one park's — Sequoia's and Kings Canyon's
    come from one NPS record — by what each photograph's title and description name.
    """
    if keywords:
        def mentions(image: dict[str, Any]) -> bool:
            text = " ".join(
                str(image.get(key) or "") for key in ("title", "caption", "altText")
            ).lower()
            return any(keyword in text for keyword in keywords)

        images = [image for image in images if mentions(image)]
    chosen = []
    seen: set[str] = set()
    for image in images:
        url = image.get("url") or ""
        if not url or url in seen or not is_public_domain_credit(image.get("credit")):
            continue
        seen.add(url)
        chosen.append(image)
        if len(chosen) == limit:
            break
    return chosen


@cache
def _load(name: str) -> Any:
    return json.loads((config.CONTENT_DIR / name).read_text())


def national_park_rows() -> list[tuple[str, dict[str, Any]]]:
    """``(NPS code, row)`` for the 63 national parks, from ``content/national-parks.json``."""
    return [(row["npsParkCode"], row) for row in _load("national-parks.json")["parks"]]


def api_code(row: dict[str, Any]) -> str:
    """The code the NPS Data API files a national park under."""
    return row.get("npsApiCode") or row["npsParkCode"]


def national_park_facts() -> dict[str, dict[str, Any]]:
    return _load("national-park-facts.json")["parks"]


def curated_sites() -> list[dict[str, Any]]:
    """Every non-NPS site the map carries: state parks, then other agencies' land."""
    return [*_load("state-parks.json")["sites"], *_load("federal-sites.json")["sites"]]


def themes() -> list[dict[str, Any]]:
    return _load("themes.json")["themes"]


def guide(place_id: str) -> dict[str, Any] | None:
    path = GUIDES_DIR / f"{place_id}.json"
    if not path.exists():
        return None
    return json.loads(path.read_text())


def guide_paths() -> list[Path]:
    return sorted(GUIDES_DIR.glob("np-*.json"))
