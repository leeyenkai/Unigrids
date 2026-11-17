"""Norway: Miljødirektoratet's protected areas, Kartverket's counties, OpenStreetMap,
Wikidata, Wikipedia, Wikimedia Commons, Open-Meteo and ``content/countries/no/``.

Identifiers carry the country (``no-np-jotunheimen``, ``no-lvo-…``, ``no-nr-…``,
``poi-no-jotunheimen-…``) and are slugged with ``ids.romanised_slug``, so "Færder" keeps
its letters. National parks keep the identifiers their content list gives them; every
other place and point of interest resolves through Norway's registries in
``content/ids/no/``, keyed on its source's own identifier.
"""

from __future__ import annotations

from typing import Any

from .assembly import assemble
from .fetching import fetch

__all__ = ["CODE", "NAME", "assemble", "fetch", "manifest_note"]

CODE = "no"
NAME = "Norway"


def manifest_note(places: list[dict[str, Any]]) -> str:
    def count(kind: str) -> int:
        return sum(1 for place in places if place["kind"] == kind)

    parks = count("nationalPark")
    # A park's summary comes from its written guide, so it counts the guides written.
    written = sum(
        1 for place in places if place["kind"] == "nationalPark" and place.get("summary")
    )
    guides = " with a guide" if written == parks else f", {written} with a written guide so far"
    return (
        f"Norway: all {parks} national parks{guides}, "
        f"{count('protectedLandscape')} landscape protection areas and "
        f"{count('natureReserve')} nature reserves of 10 km² or more, from Miljødirektoratet's "
        "Naturvernområder (NLOD 2.0; outlines simplified by Unigrids) and Kartverket's "
        "counties (CC BY 4.0). Guide prose is written for Unigrids; huts, rail lines and "
        "stations are from OpenStreetMap (ODbL); photographs are from Wikimedia Commons, each "
        "with its own credit and licence; places without a guide carry a lead adapted from "
        "Wikipedia where one exists, credited where it is shown."
    )
