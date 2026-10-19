"""OpenStreetMap roads and water for a park's extent, through Overpass.

``SPECIFICATION.md`` §12 takes roads, water and labels for the offline tiles from
OpenStreetMap, under the ODbL. Two obligations follow, and they are different from each
other:

* **Attribution**, always. It travels with the pack in ``ATTRIBUTION.md``.
* **Share-alike, on a derived *database*.** Rendered tiles are a Produced Work under the
  ODbL — an image made from the database, not the database — so tiles carry attribution
  but do not oblige the pack to publish a database. The moment the pipeline ships OSM
  *geometry* as data (the obvious temptation: filling gaps in the trail catalogue from
  OSM ways, which §8 contemplates), the pack is distributing a derived database and
  share-alike applies to it. The pack records which of the two it is, per source, rather
  than leaving it to be worked out later.

Overpass is volunteer-run and routinely busy, so queries go to one endpoint after another
and the raw response is kept: one query per park per fetch, never one per tile.
"""

from __future__ import annotations

from typing import Any

import httpx

from ..geo import BoundingBox
from . import http

ENDPOINTS = (
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
    "https://overpass.private.coffee/api/interpreter",
)

TERMS = {
    "identifier": "openstreetmap",
    "title": "OpenStreetMap, via the Overpass API",
    "url": "https://www.openstreetmap.org/copyright",
    "licence": "Open Database License (ODbL) 1.0",
    "attribution": "© OpenStreetMap contributors",
    "notes": (
        "Roads and water for the offline tiles. Rendered tiles are a Produced Work under "
        "the ODbL and owe attribution; shipping OSM geometry as data instead would make "
        "the pack a Derivative Database and trigger share-alike."
    ),
}

# Everything a topo-style park map draws, and nothing else. Buildings, landuse and
# addresses would multiply the response for detail these tiles never render.
QUERY_TEMPLATE = """[out:json][timeout:{timeout}];
(
  way["highway"]({south:.6f},{west:.6f},{north:.6f},{east:.6f});
  way["waterway"]({south:.6f},{west:.6f},{north:.6f},{east:.6f});
  way["natural"="water"]({south:.6f},{west:.6f},{north:.6f},{east:.6f});
  way["natural"="wetland"]({south:.6f},{west:.6f},{north:.6f},{east:.6f});
  way["landuse"="reservoir"]({south:.6f},{west:.6f},{north:.6f},{east:.6f});
  relation["natural"="water"]({south:.6f},{west:.6f},{north:.6f},{east:.6f});
);
out geom;
"""


def build_query(box: BoundingBox, timeout_seconds: int = 300) -> str:
    return QUERY_TEMPLATE.format(
        timeout=timeout_seconds,
        south=box.south,
        west=box.west,
        north=box.north,
        east=box.east,
    )


def download(
    session: httpx.Client, box: BoundingBox, *, record: Any = None
) -> dict[str, Any]:
    """Run one Overpass query for the box, trying each endpoint in turn."""
    query = build_query(box)
    politeness = http.Politeness(attempts=2, backoff_seconds=10.0, timeout_seconds=420.0)
    problems: list[str] = []
    for endpoint in ENDPOINTS:
        try:
            response = http.post(
                session, endpoint, data={"data": query}, politeness=politeness, expect="application"
            )
        except http.FetchError as error:
            problems.append(f"{endpoint}: {error}")
            continue
        payload = response.json()
        if "elements" not in payload:
            problems.append(f"{endpoint}: no elements in the response")
            continue
        if record is not None:
            record.add_request(endpoint, {"data": query}, elements=len(payload["elements"]))
        return payload
    raise http.FetchError("every Overpass endpoint failed: " + "; ".join(problems))


def ways(payload: dict[str, Any]) -> list[dict[str, Any]]:
    """Ways with inline geometry, including the ways inside the water relations.

    ``out geom`` puts coordinates on each element, so no node lookup is needed; a
    multipolygon water body arrives as its member ways, which is all a filled outline
    needs.
    """
    collected: list[dict[str, Any]] = []
    for element in payload.get("elements", []):
        if element.get("type") == "way" and element.get("geometry"):
            collected.append(element)
        elif element.get("type") == "relation":
            tags = element.get("tags", {})
            for member in element.get("members", []):
                if member.get("type") == "way" and member.get("geometry"):
                    collected.append({**member, "tags": tags, "from_relation": element.get("id")})
    return collected
