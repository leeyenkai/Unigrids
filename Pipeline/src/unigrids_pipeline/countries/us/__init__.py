"""The United States: the NPS Data API, the federal land agencies, PAD-US and
``content/``.

The US came first, so its identifiers carry no country prefix (``np-zion``) and its
curated files sit at the top of ``content/`` rather than under a country folder. Both stay
as they are: an identifier in a user's log must never change.

Most of what the US build reads is fetched and parsed by modules at the package's top
level (``lands_build``, ``state_parks``, ``trail_catalogue`` and the rest), which predate
countries. This package is where they are called from.
"""

from __future__ import annotations

from typing import Any

from .assembly import assemble
from .fetching import fetch

__all__ = ["CODE", "NAME", "assemble", "fetch", "manifest_note"]

CODE = "us"
NAME = "United States"


def manifest_note(places: list[dict[str, Any]]) -> str:
    others = sum(1 for place in places if place["kind"] != "nationalPark")
    parks = sum(1 for place in places if place["kind"] == "nationalPark")
    return (
        f"All {parks} national parks with a full guide, and {others:,} more places on the "
        "map: other NPS units from the NPS Data API; every state park from PAD-US; every "
        "national forest, grassland and wildlife refuge, the BLM's monuments and "
        "conservation areas, National Natural Landmarks and scenic byways from their "
        "agencies' own data. Guide prose is written for Unigrids; descriptions, fees, "
        "hours, visitor centres and photographs are the NPS's own; places with no "
        "agency prose carry a lead adapted from Wikipedia, credited where it is shown."
    )
