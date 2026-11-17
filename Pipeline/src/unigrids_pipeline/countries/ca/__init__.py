"""Canada: the Canadian Protected and Conserved Areas Database, Parks Canada's trails,
facilities, accommodation and attendance, OpenStreetMap, Wikidata, Wikipedia, Wikimedia
Commons, Open-Meteo and ``content/countries/ca/``.

Identifiers carry the country (``ca-np-banff``, ``ca-mca-…``, ``ca-pp-…``,
``poi-ca-banff-…``, ``trail-ca-…``). National parks keep the identifiers their content list
gives them; every other place, point of interest and trail resolves through Canada's
registries in ``content/ids/ca/``, keyed on its source's own identifier (``cpcad:…``,
``parkscanada:…``, ``osm:…``).
"""

from __future__ import annotations

from typing import Any

from .assembly import assemble
from .fetching import fetch

__all__ = ["CODE", "NAME", "assemble", "fetch", "manifest_note"]

CODE = "ca"
NAME = "Canada"


def manifest_note(places: list[dict[str, Any]]) -> str:
    parks = sum(1 for place in places if place["kind"] == "nationalPark")
    marine = sum(1 for place in places if place["kind"] == "marineConservationArea")
    provincial = sum(1 for place in places if place["kind"] == "provincialPark")
    written = sum(
        1 for place in places if place["kind"] == "nationalPark" and place.get("summary")
    )
    guides = " with a guide" if written == parks else f", {written} with a written guide so far"
    return (
        f"Canada: all {parks} national parks and national park reserves and Rouge National "
        f"Urban Park{guides}, {marine} national marine conservation areas, and {provincial} "
        "provincial and territorial parks of 100 km² or more, from the Canadian Protected and "
        "Conserved Areas Database (Environment and Climate Change Canada; outlines simplified "
        "by Unigrids). Trails, campgrounds, huts, visitor centres and attendance are Parks "
        "Canada's own; all of these are used under the Open Government Licence – Canada. Rail "
        "lines, stations and other huts are from OpenStreetMap (ODbL). Guide prose is written "
        "for Unigrids; photographs are from Wikimedia Commons, each with its own credit and "
        "licence; places without a guide carry a lead adapted from Wikipedia where one "
        "exists, credited where it is shown. Unigrids is not affiliated with Parks Canada and "
        "carries neither its beaver symbol nor its wordmark."
    )
