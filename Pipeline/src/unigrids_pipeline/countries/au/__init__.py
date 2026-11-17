"""Australia: the Collaborative Australian Protected Areas Database, the ABS's states and
territories, Queensland's walking tracks, OpenStreetMap, Wikidata, Wikipedia, Wikimedia
Commons, Open-Meteo and ``content/countries/au/``.

Identifiers carry the country (``au-np-kakadu``, ``au-snp-…``, ``poi-au-kakadu-…``,
``trail-au-…``). National parks with a guide keep the identifiers their content list gives
them; every other place, point of interest and trail resolves through Australia's
registries in ``content/ids/au/``, keyed on its source's own identifier
(``capad:<STATE>/<NAME>``, ``osm:…``, ``qpws:…``).
"""

from __future__ import annotations

from typing import Any

from .assembly import assemble
from .fetching import fetch

__all__ = ["CODE", "NAME", "assemble", "fetch", "manifest_note"]

CODE = "au"
NAME = "Australia"


def manifest_note(places: list[dict[str, Any]]) -> str:
    parks = sum(1 for place in places if place["kind"] == "nationalPark")
    second = sum(1 for place in places if place["kind"] == "stateNationalPark")
    written = sum(
        1 for place in places if place["kind"] == "nationalPark" and place.get("summary")
    )
    guides = " with a guide" if written == parks else f", {written} with a written guide so far"
    return (
        f"Australia: {parks} national parks{guides} — the Commonwealth's six and the state "
        "parks in a World Heritage property or named their state's flagship — and "
        f"{second} other state and territory national parks, from the Collaborative "
        "Australian Protected Areas Database 2024 (© Commonwealth of Australia, DCCEEW, "
        "CC BY 4.0; outlines simplified by Unigrids) and the ABS's states and territories "
        "(CC BY 4.0). Queensland's walking tracks and their grades are the Queensland Parks "
        "and Wildlife Service's (© State of Queensland, CC BY 4.0); other trails, rail "
        "lines, stations, visitor centres, campgrounds and huts are from OpenStreetMap "
        "(ODbL). Guide prose is written for Unigrids; photographs are from Wikimedia "
        "Commons, each with its own credit and licence; places without a guide carry a "
        "lead adapted from Wikipedia where one exists, credited where it is shown. Unigrids "
        "is not affiliated with Parks Australia or any state or territory park agency and "
        "carries none of their logos."
    )
