"""New Zealand: DOC's Public Conservation Land, huts, campsites, visitor centres and
tracks, Stats NZ's regions, OpenStreetMap, Wikidata, Wikipedia, Wikimedia Commons,
Open-Meteo and ``content/countries/nz/``.

Identifiers carry the country (``nz-np-tongariro``, ``nz-cp-…``, ``poi-nz-tongariro-…``,
``trail-nz-…``). National parks keep the identifiers their content list gives them; every
other place, point of interest and trail resolves through New Zealand's registries in
``content/ids/nz/``, keyed on its source's own identifier (``napalis:…``, ``doc:asset/…``).
"""

from __future__ import annotations

from typing import Any

from .assembly import assemble
from .fetching import fetch

__all__ = ["CODE", "NAME", "assemble", "fetch", "manifest_note"]

CODE = "nz"
NAME = "New Zealand"


def manifest_note(places: list[dict[str, Any]]) -> str:
    parks = sum(1 for place in places if place["kind"] == "nationalPark")
    second = sum(1 for place in places if place["kind"] == "conservationPark")
    written = sum(
        1 for place in places if place["kind"] == "nationalPark" and place.get("summary")
    )
    guides = " with a guide" if written == parks else f", {written} with a written guide so far"
    return (
        f"New Zealand: all {parks} national parks{guides} and {second} conservation and "
        "forest parks of 5 km² or more, from the Department of Conservation's Public "
        "Conservation Land (CC BY 4.0, Crown Copyright: Department of Conservation Te Papa "
        "Atawhai; outlines simplified by Unigrids) and Stats NZ's regions (CC BY 4.0). Huts, "
        "campsites, visitor centres and tracks are DOC's own (CC BY 4.0); rail lines and "
        "stations are from OpenStreetMap (ODbL). Guide prose is written for Unigrids; "
        "photographs are from Wikimedia Commons, each with its own credit and licence; "
        "places without a guide carry a lead adapted from Wikipedia where one exists, "
        "credited where it is shown. Unigrids is not affiliated with DOC and carries no DOC "
        "logo."
    )
