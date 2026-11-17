"""Japan: the Ministry of the Environment's 35 national parks and 58 quasi-national
parks, with ``content/countries/jp/``.

Japan's identifiers carry their country (``jp-np-shiretoko``, ``jp-qnp-ontakesan``,
``poi-jp-shiretoko-…``). National parks keep the identifier their content entry gives
them; quasi-national parks, sights and huts resolve through the committed registries in
``content/ids/jp/``, keyed on the source's own name or identifier.

Fetching is in ``fetching``, assembly in ``assembly``; the Ministry's pages and
statistics are read by ``moe``, its Shapefile by ``shapefile``, and the polygon work —
merging a park's zones into its outline, OSM multipolygons, prefecture sampling — is in
``geometry``.
"""

from __future__ import annotations

from typing import Any

from .assembly import assemble
from .fetching import fetch

__all__ = ["CODE", "NAME", "assemble", "fetch", "manifest_note"]

CODE = "jp"
NAME = "Japan"


def manifest_note(places: list[dict[str, Any]]) -> str:
    parks = sum(1 for place in places if place["kind"] == "nationalPark")
    quasi = sum(1 for place in places if place["kind"] == "quasiNationalPark")
    return (
        f"Japan: all {parks} national parks with a guide, their areas and designation "
        f"years from the Ministry of the Environment's national park table, outlines from "
        f"its zone file and 2024 visitors from its statistics; and "
        f"{quasi} quasi-national parks from the Ministry's list, outlined from "
        "OpenStreetMap where it maps them and otherwise shown as a point, with leads "
        "adapted from Wikipedia. Prefectures from Natural Earth; huts and rail from "
        "OpenStreetMap; photographs from Wikimedia Commons, credited individually."
    )
