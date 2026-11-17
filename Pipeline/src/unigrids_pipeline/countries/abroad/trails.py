"""The trail catalogue abroad, measured exactly as the US one is.

At home the catalogue is NPS Public Trails measured on 3DEP (``trail_catalogue``). Abroad
the line comes from the best source each country has, and the measuring does not change:

* **Norway: Kartverket's Turrutebasen**, the national database of marked, maintained
  routes (``docs/sources-japan-norway.md``, N9, N10). The WFS hands out segments; each
  segment lists every route that uses it, by route number (``rutenummer``, a local code
  such as ``jot31``) and name. A route is the segments that carry its number, kept where
  they lie in the park. A route the database names only "Ukjent" (unknown) is left out,
  as the US leaves out unnamed trails: its line is real, but nothing says what to call
  it. The route's own grade (``gradering``) travels with it as published — G, B, R, S,
  or I for a route deliberately left ungraded.
* **Japan: OpenStreetMap**, through Overpass (J7, B3): ``route=hiking`` relations and
  named ``highway=path|footway`` ways, one query per park. Ways sharing a name are one
  trail only where they lie together: "遊歩道" (promenade) names dozens of unrelated
  paths across a park, and joining them would make a trail nobody could walk.
* **A Norwegian park with no Turrutebasen route** is filled from OpenStreetMap the same
  way. Svalbard's parks and the other trailless ones simply get none.
* **New Zealand: DOC Tracks**, the Department of Conservation's register of the tracks it
  maintains (CC BY 4.0), read whole by the New Zealand fetch; ``countries.nz.tracks`` turns
  its records into routes, with DOC's walking track category. A park DOC's layer leaves
  without a track is filled from OpenStreetMap, read out of Geofabrik's extract.
* **Canada: Parks Canada's trails** (OGL–Canada), the line layer of the trails the agency
  is responsible for, read whole by the Canadian fetch; ``countries.ca.pctrails`` turns its
  records into routes, with Parks Canada's summer difficulty rating. A park the layer
  leaves without a trail is filled from OpenStreetMap, read out of Geofabrik's provincial
  extracts.

Then, exactly as at home: segments are chained (``trails.chain``), laid in walking order,
resampled every 30 m, sampled on the elevation model (abroad: Copernicus GLO-30), smoothed
over 90 m, accumulated with a 3 m dead band, and kept as a 60-point profile; a line that
closes on itself is a loop; features come from the trail's own name; sights within 200 m
are listed in walking order. Identifiers are minted through the country's trail registry
(``ids.country_trail_id``), keyed on the source's own identifier, never on a name alone.

Shipping OSM lines as data makes the catalogue a Derivative Database under the ODbL, as
it already is for Sequoia and Kings Canyon: attributed in the app, and available under the
same licence. Turrutebasen is CC BY 4.0, credited «©Kartverket».
"""

from __future__ import annotations

import json
import math
import re
import time
import xml.etree.ElementTree as ElementTree
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import httpx
import numpy as np

from ... import config, ids, measure, outline, rawstore, trail_catalogue, trails
from ...geo import BoundingBox, Coordinate, distance_m, line_length_m
from ...rawstore import FetchRecord, SourceTerms
from ...sources import http, osm, osm_pbf
from . import elevation

Record = dict[str, Any]

# The measuring constants are the US catalogue's, by reference, so the two cannot drift.
STATION_INTERVAL_M = trail_catalogue.STATION_INTERVAL_M
PROFILE_POINTS = trail_catalogue.PROFILE_POINTS
MIN_LENGTH_M = trail_catalogue.MIN_LENGTH_M
LINE_TOLERANCE_DEGREES = trail_catalogue.LINE_TOLERANCE_DEGREES
BOUNDARY_BUFFER_DEGREES = trail_catalogue.BOUNDARY_BUFFER_DEGREES

COUNTRIES = ("jp", "no", "nz", "ca")

TURRUTEBASEN = "no-turrutebasen"
TURRUTEBASEN_WFS = "https://wfs.geonorge.no/skwms1/wfs.turogfriluftsruter"
TURRUTEBASEN_DATASET = (
    "https://kartkatalog.geonorge.no/metadata/d1422d17-6d95-4ef1-96ab-8af31744dd63"
)
GRADE_PUBLISHER = "Kartverket (Turrutebasen)"
GRADES = frozenset({"G", "B", "R", "S", "I"})
"""Turrutebasen's ``gradering`` codes: Enkel, Middels, Krevende, Ekspert, Ikke gradert."""

UNNAMED = frozenset({"", "ukjent", "ukjend", "unknown"})
"""Route names that are the database saying it has none."""

OSM_TRAIL_SOURCES = {
    "jp": "jp-osm-trails", "no": "no-osm-trails", "nz": "nz-osm-trails", "ca": "ca-osm-trails",
}
OSM_TRAIL_KINDS = "path|footway"
OSM_PAUSE_SECONDS = 10.0
"""Between one park's Overpass query and the next: the servers are volunteer-run."""

CLUSTER_REACH_M = 500.0
"""Ways sharing a name are one trail when each lies this close to another of them."""

TRAILHEAD_KINDS = ("visitorCentre", "campground", "trailhead")
"""Points of interest whose nearness decides where a walk starts, as visitor centres and
campgrounds do at home; abroad a guide may also name a trailhead."""

SIGHT_KINDS = ("sight", "viewpoint")

TURRUTEBASEN_TERMS = SourceTerms(
    identifier="kartverket-turrutebasen",
    title="Kartverket, Tur- og friluftsruter (Turrutebasen): hiking routes (Fotrute) by WFS",
    url=TURRUTEBASEN_WFS,
    licence="CC BY 4.0",
    attribution="©Kartverket",
    notes=(
        "Marked, maintained routes, one query per national park's box in EPSG:4326. "
        "Crowd-sourced through «Rett i kartet», so completeness varies; route numbers are "
        "local codes. Grades are quoted as codes, never the criteria text."
    ),
)

OSM_TRAIL_TERMS = SourceTerms(
    identifier="openstreetmap-trails-abroad",
    title="OpenStreetMap hiking routes and named footpaths, via the Overpass API",
    url="https://www.openstreetmap.org/copyright",
    licence="Open Database License (ODbL) 1.0",
    attribution="© OpenStreetMap contributors (ODbL)",
    notes=(
        "route=hiking relations and named highway=path|footway ways, one query per park. "
        "Shipped as data, so the trails taken from it are a Derivative Database under the "
        "ODbL: attributed in the app, and available under the same licence."
    ),
)

OSM_QUERY = """[out:json][timeout:600];
(
  relation["route"="hiking"]({box});
  way["highway"~"^({kinds})$"]["name"]({box});
);
out geom;
"""
"""Whole geometry, not clipped to the box, so the answers for a box's quarters agree on
every element they share and merge by id."""


@dataclass
class Route:
    """One trail before it is measured: its source's key, name and line."""

    key: str
    """The registry key: ``turrutebasen:<park>/<route number>`` or ``osm:relation/<id>``."""
    name: str
    latin_name: str | None
    """A Latin-script name to make the identifier from, or ``None`` to use the key."""
    source: str
    segments: list[list[Coordinate]] = field(default_factory=list)
    grade: Record | None = None
    uses: str | None = None
    names: tuple[str, ...] = ()
    """Every form of the name, for reading features from it (``name``, ``name:en``)."""
    extra: Record = field(default_factory=dict)
    """Fields the source publishes that the record carries as they are (DOC's category,
    whether dogs may come)."""

    @property
    def bikes_allowed(self) -> bool:
        return bool(self.uses and "bicycle" in self.uses.lower())


# MARK: - Entry points


def build(
    country: str,
    parks: list[Record],
    outlines: dict[str, list[outline.Polygon]],
    sights: dict[str, list[Record]],
    *,
    online: bool,
    registry: ids.Registry | None = None,
    dem: elevation.CopernicusDEM | None = None,
) -> list[Record]:
    """Every catalogue trail in ``country``'s parks, as the app's ``Trail`` decodes it.

    ``parks`` are the country's national parks (each with ``id``); ``outlines`` maps a
    park to its polygons; ``sights`` maps a park to its points of interest (any kind:
    sights and viewpoints are matched along trails, visitor centres, campgrounds and
    trailheads decide where a walk starts). Pass the country's trail ``registry`` and put
    it in ``Contribution.registries`` so the frame saves it; without one, identifiers are
    resolved against the committed file and not saved. ``online`` lets a missing park's
    routes and elevation tiles be fetched; offline the build reads the raw store.
    """
    if country not in COUNTRIES:
        raise ValueError(f"no trail catalogue for {country!r}; known: {', '.join(COUNTRIES)}")
    registry = registry or ids.country_registry(country, "trails")
    model = dem or elevation.CopernicusDEM(online=online)
    catalogue: list[Record] = []
    for park in parks:
        polygons = outlines.get(park["id"])
        if not polygons:
            continue
        routes = park_routes(country, park, polygons, online=online)
        pois = sights.get(park["id"]) or []
        records = measure_park(country, park, routes, model, pois, registry)
        # A track that crosses from one park into the next (the Routeburn, between
        # Fiordland and Mount Aspiring) is one trail: it stays with the park it was first
        # listed in, whose name its identifier carries.
        listed = {trail["id"] for trail in catalogue}
        catalogue.extend(record for record in records if record["id"] not in listed)
    measured = sum(1 for trail in catalogue if "gainMetres" in trail)
    kilometres = sum(trail["lengthMetres"] for trail in catalogue) / 1000
    print(
        f"    trails ({country}): {len(catalogue)} in "
        f"{len({trail['placeID'] for trail in catalogue})} parks, {kilometres:,.0f} km, "
        f"{measured} with elevation"
    )
    return catalogue


def fetch(
    country: str,
    parks: list[Record],
    outlines: dict[str, list[outline.Polygon]],
    *,
    refresh: bool = False,
    elevation_tiles: bool = True,
    osm_extract: Path | None = None,
) -> Path:
    """Download the routes ``build`` reads into ``raw/<today>/``, then the elevation tiles
    the kept routes cross. Resumes where an earlier run stopped; a park Overpass could not
    answer is named at the end and left for the next run. Returns today's directory.

    Norway's routes come first for every park, since they do not depend on Overpass;
    OpenStreetMap is then asked only for the parks Turrutebasen leaves without a route.
    With ``osm_extract`` (a Geofabrik ``.osm.pbf``), every park's OpenStreetMap file not
    yet fetched is read out of the extract in one pass instead of asked of Overpass.
    """
    if country not in COUNTRIES:
        raise ValueError(f"no trail catalogue for {country!r}; known: {', '.join(COUNTRIES)}")
    version = rawstore.today()
    located = [(park, outlines.get(park["id"])) for park in parks]
    for park, polygons in located:
        if not polygons:
            print(f"    trails ({country}): {park['id']} has no outline to search within")
    located = [(park, polygons) for park, polygons in located if polygons]
    model = elevation.CopernicusDEM(online=True) if elevation_tiles else None
    left: list[str] = []
    if osm_extract is not None:
        source = OSM_TRAIL_SOURCES[country]
        fetch_osm_extract(
            country,
            [(park, polygons) for park, polygons in located
             if refresh or _latest(source, park["id"]) is None],
            version,
            osm_extract,
        )
    with client() as session:
        if country == "no":
            for park, polygons in located:
                if refresh or _latest(TURRUTEBASEN, park["id"]) is None:
                    fetch_turrutebasen(session, park, polygons, version)
        for park, polygons in located:
            routes: list[Route] = []
            if country == "no":
                features = _read_features(TURRUTEBASEN, park["id"])
                if features is None:
                    # Kartverket did not answer: not the same as a park with no routes.
                    left.append(park["id"])
                    continue
                routes = turrutebasen_routes(park, features, polygons)
            elif country in AGENCY_TRAILS:
                agency = agency_routes(country, park, polygons)
                if agency is None:
                    # The country's fetch reads the agency's layer first; without it, wait.
                    left.append(park["id"])
                    continue
                routes = agency
            if is_thin(country, routes):
                wanted = refresh or _latest(OSM_TRAIL_SOURCES[country], park["id"]) is None
                if wanted and fetch_osm(session, country, park, polygons, version) is None:
                    left.append(park["id"])
                routes = with_osm(
                    routes, osm_routes(country, park, _read_osm(country, park["id"]), polygons)
                )
            if model is not None:
                for route in routes:
                    box = _box(route.segments)
                    if box is not None:
                        model.fetch_box(box.south, box.west, box.north, box.east)
    if model is not None:
        model.close()
    if left:
        print(f"    trails ({country}): no answer for {', '.join(left)}; "
              "run again to fetch them")
    return config.RAW_DIR / version


def park_routes(
    country: str, park: Record, polygons: list[outline.Polygon], *, online: bool
) -> list[Route]:
    """A park's routes from the raw store: Turrutebasen's for Norway where it has any,
    OpenStreetMap's otherwise. Online, what was never fetched is fetched first."""
    with client() as session:
        if country == "no":
            if online and _latest(TURRUTEBASEN, park["id"]) is None:
                fetch_turrutebasen(session, park, polygons, rawstore.today())
            features = _read_features(TURRUTEBASEN, park["id"])
            if features is None:
                print(f"    trails (no): no Turrutebasen routes fetched for {park['id']}")
                return []
            if routes := turrutebasen_routes(park, features, polygons):
                return routes
        agency: list[Route] = []
        if country in AGENCY_TRAILS:
            found = agency_routes(country, park, polygons)
            if found is None:
                print(f"    trails ({country}): no {AGENCY_TRAILS[country]} fetched for "
                      f"{park['id']}")
                return []
            agency = found
            if not is_thin(country, agency):
                return agency
        if online and _latest(OSM_TRAIL_SOURCES[country], park["id"]) is None:
            fetch_osm(session, country, park, polygons, rawstore.today())
    return with_osm(agency, osm_routes(country, park, _read_osm(country, park["id"]), polygons))


AGENCY_TRAILS = {"nz": "DOC Tracks", "ca": "Parks Canada trails"}
"""Countries whose park agency publishes its own trail layer, read before OpenStreetMap."""

THIN_AGENCY_TRAILS = {"ca": 5}
"""Fewer agency trails than this in a park and OpenStreetMap fills in beside them. Parks
Canada's layer is part-way through a migration and holds two of Jasper's hundreds; DOC's
register is whole, so New Zealand fills only a park it leaves empty."""


def is_thin(country: str, routes: list[Route]) -> bool:
    """Whether a park's agency trails are too few to stand alone."""
    return len(routes) < THIN_AGENCY_TRAILS.get(country, 1)


def with_osm(agency: list[Route], osm: list[Route]) -> list[Route]:
    """The agency's routes, and OpenStreetMap's whose names the agency's do not take."""
    taken = {ids.slug(route.name) for route in agency}
    return sorted([*agency, *(route for route in osm if ids.slug(route.name) not in taken)],
                  key=lambda route: (route.name, route.key))


def agency_routes(
    country: str, park: Record, polygons: list[outline.Polygon]
) -> list[Route] | None:
    """The park's routes from its agency's own layer, or None if that layer was never
    fetched (not the same as a park the layer leaves without a trail)."""
    if country == "nz":
        from ..nz import tracks as doc_tracks

        doc_features = doc_tracks.read_features()
        return None if doc_features is None else doc_tracks.routes(park, doc_features, polygons)
    if country == "ca":
        from ..ca import pctrails

        pc_features = pctrails.read_features()
        return None if pc_features is None else pctrails.routes(park, pc_features, polygons)
    return None


# MARK: - Turrutebasen


TURRUTEBASEN_TILE_DEGREES = (0.25, 0.5)
"""Latitude and longitude span of one WFS request. The service answers a park-sized box in
one slow stream — minutes for Jostedalsbreen's — and tiles keep each answer quick and a
retry cheap."""


def fetch_turrutebasen(
    session: httpx.Client, park: Record, polygons: list[outline.Polygon], version: str
) -> Path | None:
    """Every hiking-route segment in the park's box, stored as GeoJSON features.

    The box is asked for in tiles; a segment two tiles both return is kept once, by its
    ``lokalId``. A tile that fails fails the park, so a partial answer is never stored.
    """
    box = _search_box(polygons)
    if box is None:
        return None
    features: dict[str, Record] = {}
    requests: list[Record] = []
    for tile in search_tiles(box):
        # EPSG:4326 in WFS 2.0 is latitude first: south, west, north, east.
        bbox = f"{tile.south:.5f},{tile.west:.5f},{tile.north:.5f},{tile.east:.5f}"
        parameters = {
            "service": "WFS",
            "version": "2.0.0",
            "request": "GetFeature",
            "typeNames": "app:Fotrute",
            "srsName": "urn:ogc:def:crs:EPSG::4326",
            "bbox": f"{bbox},urn:ogc:def:crs:EPSG::4326",
        }
        try:
            response = http.get(session, TURRUTEBASEN_WFS, params=parameters, expect="text/xml")
        except http.FetchError as error:
            print(f"    {TURRUTEBASEN}: {park['id']} failed ({error})")
            return None
        for feature in parse_fotruter(response.content):
            properties = feature["properties"]
            key = properties.get("lokalId") or json.dumps(feature["geometry"])
            features.setdefault(key, feature)
        requests.append(parameters)
    directory = rawstore.version_directory(TURRUTEBASEN, version)
    path = directory / f"{park['id']}.geojson"
    collected = list(features.values())
    path.write_text(
        json.dumps({"type": "FeatureCollection", "features": collected}, ensure_ascii=False)
    )
    _write_record(directory, TURRUTEBASEN_TERMS, path, TURRUTEBASEN_WFS,
                  {"tiles": [request["bbox"] for request in requests]}, features=len(collected))
    print(f"    {TURRUTEBASEN}/{park['id']}: {len(collected)} segments", flush=True)
    return path


def search_tiles(box: BoundingBox) -> list[BoundingBox]:
    """A box cut into tiles no larger than :data:`TURRUTEBASEN_TILE_DEGREES`."""
    height, width = TURRUTEBASEN_TILE_DEGREES
    rows = max(1, math.ceil((box.north - box.south) / height))
    columns = max(1, math.ceil((box.east - box.west) / width))
    step_y = (box.north - box.south) / rows
    step_x = (box.east - box.west) / columns
    return [
        BoundingBox(
            west=box.west + column * step_x,
            south=box.south + row * step_y,
            east=box.west + (column + 1) * step_x,
            north=box.south + (row + 1) * step_y,
        )
        for row in range(rows)
        for column in range(columns)
    ]


def parse_fotruter(payload: bytes) -> list[Record]:
    """Turrutebasen's GML as GeoJSON features: each segment's line, its marking, and the
    routes that use it (``routes``: number, name, grade, maintainer, special type)."""
    features: list[Record] = []
    root = ElementTree.fromstring(payload)
    for element in root.iter():
        if _local(element.tag) != "Fotrute":
            continue
        lines = [
            line
            for node in element.iter()
            if _local(node.tag) == "posList" and len(line := _positions(node.text or "")) >= 2
        ]
        if not lines:
            continue
        routes = [
            {
                "number": _child_text(info, "rutenummer"),
                "name": _child_text(info, "rutenavn"),
                "grade": _child_text(info, "gradering"),
                "maintainer": _child_text(info, "vedlikeholdsansvarlig"),
                "special": _child_text(info, "spesialFotrutetype"),
            }
            for info in element.iter()
            if _local(info.tag) == "FotruteInfo"
        ]
        features.append({
            "type": "Feature",
            "properties": {
                "lokalId": _child_text(element, "lokalId"),
                "marked": _child_text(element, "merking"),
                "follows": _child_text(element, "ruteFølger"),
                "routes": routes,
            },
            "geometry": (
                {"type": "LineString", "coordinates": lines[0]}
                if len(lines) == 1
                else {"type": "MultiLineString", "coordinates": lines}
            ),
        })
    return features


def _local(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def _child_text(element: ElementTree.Element, name: str) -> str:
    for node in element.iter():
        if _local(node.tag) == name:
            return (node.text or "").strip()
    return ""


def _positions(text: str) -> list[list[float]]:
    """A GML ``posList`` in EPSG:4326 (latitude first) as GeoJSON ``[lon, lat]`` pairs."""
    values = [float(value) for value in text.split()]
    return [[round(values[i + 1], 6), round(values[i], 6)] for i in range(0, len(values) - 1, 2)]


def turrutebasen_routes(
    park: Record, features: list[Record] | None, polygons: list[outline.Polygon]
) -> list[Route]:
    """The park's named routes: segments joined by route number (by name where a route has
    no number), kept where they lie in the park."""
    if not features:
        return []
    slug = park_slug(park["id"])
    box = _outline_box(polygons)
    groups: dict[str, dict[str, Any]] = {}
    for position, feature in enumerate(features):
        properties = feature.get("properties") or {}
        lines = _lines(feature.get("geometry") or {})
        kept = [line for line in lines if _inside(polygons, box, line)]
        if not kept:
            continue
        segment_id = properties.get("lokalId") or f"feature-{position:06d}"
        for info in properties.get("routes") or []:
            name = (info.get("name") or "").strip()
            number = (info.get("number") or "").strip()
            if name.lower() in UNNAMED:
                name = ""
            if not number and not name:
                continue
            group_key = number or f"name:{name}"
            group = groups.setdefault(
                group_key,
                {"number": number, "names": Counter(), "grades": Counter(), "segments": {}},
            )
            if name:
                group["names"][name] += 1
            if grade := (info.get("grade") or "").strip().upper():
                group["grades"][grade] += 1
            for index, line in enumerate(kept):
                group["segments"].setdefault(f"{segment_id}#{index}", line)
    routes: list[Route] = []
    for group in groups.values():
        if not group["names"]:
            continue  # "Ukjent" throughout: a line with no name to give it
        name = group["names"].most_common(1)[0][0]
        local = group["number"] or min(group["segments"]).split("#", 1)[0]
        routes.append(Route(
            key=f"turrutebasen:{slug}/{local}",
            name=name,
            latin_name=name,
            source="kartverket",
            segments=list(group["segments"].values()),
            grade=published_grade(group["grades"]),
            names=(name,),
        ))
    return sorted(routes, key=lambda route: (route.name, route.key))


def published_grade(grades: Counter[str]) -> Record | None:
    """The route's grade as Turrutebasen publishes it, when its segments agree on one.

    ``I`` is a grade too — "Ikke gradert", deliberately ungraded — and is kept as
    published. Segments that disagree leave the route without one rather than choosing.
    """
    known = {grade for grade in grades if grade in GRADES}
    if len(known) != 1:
        return None
    return {
        "system": "norwegianMarking",
        "grade": known.pop(),
        "publisher": GRADE_PUBLISHER,
        "sourceURL": TURRUTEBASEN_DATASET,
    }


# MARK: - OpenStreetMap


def fetch_osm(
    session: httpx.Client,
    country: str,
    park: Record,
    polygons: list[outline.Polygon],
    version: str,
) -> Path | None:
    """The park's hiking relations and named footpaths: one Overpass query for its box,
    or its quarters where the whole box is more than a server will answer."""
    box = _search_box(polygons)
    if box is None:
        return None
    source = OSM_TRAIL_SOURCES[country]
    try:
        elements, asked = overpass_box(session, box, trail_query)
    except http.FetchError as error:
        print(f"    {source}: {park['id']} failed ({error})")
        return None
    finally:
        time.sleep(OSM_PAUSE_SECONDS)
    path = write_osm(country, park, elements, version, OSM_TRAIL_TERMS, asked[0][0],
                     {"data": [query for _, query in asked]})
    print(f"    {source}/{park['id']}: {len(elements)} elements"
          f"{f' in {len(asked)} queries' if len(asked) > 1 else ''}", flush=True)
    return path


def write_osm(
    country: str,
    park: Record,
    elements: list[Record],
    version: str,
    terms: SourceTerms,
    url: str,
    parameters: Record,
) -> Path:
    """One park's OpenStreetMap answer, saved where ``_read_osm`` finds it."""
    directory = rawstore.version_directory(OSM_TRAIL_SOURCES[country], version)
    path = directory / f"{park['id']}.json"
    path.write_text(json.dumps({"elements": elements}, ensure_ascii=False))
    _write_record(directory, terms, path, url, parameters, elements=len(elements))
    return path


def extract_request(park: Record, polygons: list[outline.Polygon]) -> osm_pbf.Request | None:
    """:data:`OSM_QUERY` over the park's search box, as a read of a Geofabrik extract."""
    box = _search_box(polygons)
    if box is None:
        return None
    # Rounded as ``trail_query`` writes the box, so an edge case lands as Overpass had it.
    return osm_pbf.Request(
        name=park["id"], trails=osm_pbf.rounded((box.south, box.west, box.north, box.east), 5),
        trail_kinds=OSM_TRAIL_KINDS,
    )


OSM_EXTRACT_TERMS = SourceTerms(
    identifier="openstreetmap-trails-abroad",
    title="OpenStreetMap hiking routes and named footpaths, read from a Geofabrik extract",
    url="https://www.openstreetmap.org/copyright",
    licence="Open Database License (ODbL) 1.0",
    attribution="© OpenStreetMap contributors (ODbL)",
    notes=(
        "route=hiking relations and named highway=path|footway ways touching each park's "
        "box, read out of the country's Geofabrik .osm.pbf in Overpass's `out geom` shape "
        "(whole, unclipped). Shipped as data: a Derivative Database under the ODbL."
    ),
)


def fetch_osm_extract(
    country: str,
    located: list[tuple[Record, list[outline.Polygon]]],
    version: str,
    extract: Path,
    *,
    selected: dict[str, list[Record]] | None = None,
) -> list[Path]:
    """Each park's trail file read out of a Geofabrik extract, in Overpass's shape, so
    ``osm_routes`` reads it as it reads an Overpass answer and the keys do not move.
    ``selected`` is a selection already made (the Japanese fetch reads trails, huts and
    rail in one pass); without it the extract is read here."""
    requests = [
        (park, request) for park, polygons in located
        if (request := extract_request(park, polygons)) is not None
    ]
    if not requests:
        return []
    if selected is None:
        selected = osm_pbf.select(extract, [request for _, request in requests])
    described = osm_pbf.describe(extract)
    paths = []
    for park, request in requests:
        elements = selected[request.name]
        paths.append(write_osm(
            country, park, elements, version, OSM_EXTRACT_TERMS, described["url"],
            {**described, "query": trail_query(_as_box(request.trails))},
        ))
        print(f"    {OSM_TRAIL_SOURCES[country]}/{park['id']}: {len(elements)} elements "
              "from the extract", flush=True)
    return paths


def _as_box(box: tuple[float, float, float, float] | None) -> BoundingBox:
    if box is None:
        raise ValueError("a trail request without a box")
    south, west, north, east = box
    return BoundingBox(west=west, south=south, east=east, north=north)


def trail_query(box: BoundingBox) -> str:
    area = f"{box.south:.5f},{box.west:.5f},{box.north:.5f},{box.east:.5f}"
    return OSM_QUERY.format(box=area, kinds=OSM_TRAIL_KINDS)


MAX_SPLITS = 3
"""How many times a box is quartered before the fetch gives up: 64 queries at most."""


def overpass_box(
    session: httpx.Client,
    box: BoundingBox,
    query_for: Any,
    *,
    depth: int = 0,
) -> tuple[list[Record], list[tuple[str, str]]]:
    """Every element ``query_for(box)`` selects. A box no endpoint answers whole is asked
    for in quarters and the answers merged by element, so a park too big for a busy server
    is still fetched entire — or not at all. Returns the elements and each
    ``(endpoint, query)`` asked."""
    query = query_for(box)
    try:
        payload, endpoint = overpass(session, query)
        return list(payload["elements"]), [(endpoint, query)]
    except http.FetchError:
        if depth >= MAX_SPLITS or not any(e not in _UNREACHABLE for e in OVERPASS_ENDPOINTS):
            raise
    merged: dict[tuple[str, int], Record] = {}
    asked: list[tuple[str, str]] = []
    middle_lat, middle_lon = (box.south + box.north) / 2, (box.west + box.east) / 2
    for south, north in ((box.south, middle_lat), (middle_lat, box.north)):
        for west, east in ((box.west, middle_lon), (middle_lon, box.east)):
            quarter = BoundingBox(west=west, south=south, east=east, north=north)
            elements, queries = overpass_box(session, quarter, query_for, depth=depth + 1)
            for element in elements:
                merged[(element["type"], element["id"])] = element
            asked.extend(queries)
    return list(merged.values()), asked


OSM_POLITENESS = http.Politeness(attempts=4, backoff_seconds=10.0, timeout_seconds=420.0)
OVERPASS_ENDPOINTS = (*osm.ENDPOINTS, "https://maps.mail.ru/osm/tools/overpass/api/interpreter")
"""The shared endpoints, then VK Maps' public instance as one more to try."""
_UNREACHABLE: set[str] = set()


def client() -> httpx.Client:
    """Long reads for big answers, but a short connect: a server that does not pick up in
    twenty seconds is down, not busy."""
    return httpx.Client(
        headers={"User-Agent": http.USER_AGENT},
        timeout=httpx.Timeout(600.0, connect=20.0),
        follow_redirects=True,
    )


_CHECKED: set[str] = set()
PROBE = "[out:json][timeout:10];node(0,0,0,0);out;"


def _answers(endpoint: str) -> bool:
    """Whether an endpoint is there at all: it answers a trivial query with anything —
    even a 504 from a busy instance's gateway, which a retry gets past — within half a
    minute. Asked once a run: a server that accepts the connection and then says nothing
    for ten minutes would otherwise cost ten minutes a park.
    """
    if endpoint in _CHECKED:
        return endpoint not in _UNREACHABLE
    _CHECKED.add(endpoint)
    alive = False
    for _ in range(2):
        try:
            with httpx.Client(headers={"User-Agent": http.USER_AGENT}, timeout=30.0) as probe:
                probe.post(endpoint, data={"data": PROBE})
            alive = True
            break
        except httpx.HTTPError:
            time.sleep(3)
    if not alive:
        print(f"    overpass: {endpoint} does not answer; not asked this run")
        _UNREACHABLE.add(endpoint)
    return alive


def overpass(session: httpx.Client, query: str) -> tuple[Record, str]:
    """Run a query on the first Overpass endpoint that answers it whole.

    An endpoint that refuses the connection or lets a query time out is not asked again
    this run — a server too busy for one park is too busy for the next — and an answer
    whose ``remark`` reports a runtime error (a timeout, a memory limit) is partial and is
    not kept: a park's trails from half a query would read as all of them.
    """
    problems: list[str] = []
    for endpoint in OVERPASS_ENDPOINTS:
        if endpoint in _UNREACHABLE or not _answers(endpoint):
            continue
        try:
            response = http.post(
                session, endpoint, data={"data": query}, politeness=OSM_POLITENESS,
                expect="application",
            )
            payload = response.json()
        except (http.FetchError, ValueError) as error:
            if any(sign in str(error) for sign in ("ConnectError", "Timeout")):
                _UNREACHABLE.add(endpoint)
            problems.append(f"{endpoint}: {error}")
            continue
        remark = str(payload.get("remark") or "")
        if "elements" not in payload or "error" in remark.lower():
            problems.append(f"{endpoint}: {remark or 'no elements in the answer'}")
            continue
        return payload, endpoint
    raise http.FetchError("no Overpass endpoint answered: " + "; ".join(problems)[:600])


def osm_routes(
    country: str, park: Record, payload: Record | None, polygons: list[outline.Polygon]
) -> list[Route]:
    """Hiking relations, one trail each, then named footpaths joined by name where they
    lie together; a footpath group named as a relation is that relation's line."""
    if not payload:
        return []
    box = _outline_box(polygons)
    routes: list[Route] = []
    relation_names: set[str] = set()
    by_name: dict[str, list[Record]] = {}
    for element in payload.get("elements") or []:
        tags = element.get("tags") or {}
        if element.get("type") == "relation" and tags.get("route") == "hiking":
            display = _display_name(country, tags)
            if not display:
                continue
            segments = [
                line
                for member in element.get("members") or []
                if member.get("type") == "way"
                and (line := _osm_line(member.get("geometry")))
                and _inside(polygons, box, line)
            ]
            if not segments:
                continue
            relation_names.update(name for name in _names(tags))
            routes.append(Route(
                key=f"osm:relation/{element['id']}",
                name=display,
                latin_name=_latin_name(country, tags),
                source="osm",
                segments=segments,
                uses=_osm_uses(tags),
                names=_names(tags),
            ))
        elif element.get("type") == "way" and _is_named_footpath(tags):
            line = _osm_line(element.get("geometry"))
            if line and _inside(polygons, box, line):
                by_name.setdefault(tags["name"].strip(), []).append({**element, "line": line})
    for name, ways in by_name.items():
        if name in relation_names:
            continue
        for cluster in _clusters(ways):
            tags = cluster[0].get("tags") or {}
            english = next(
                (en for way in cluster if (en := (way.get("tags") or {}).get("name:en"))), None
            )
            if english:
                tags = {**tags, "name:en": english}
            routes.append(Route(
                key=f"osm:way/{min(way['id'] for way in cluster)}",
                name=_display_name(country, tags) or name,
                latin_name=_latin_name(country, tags),
                source="osm",
                segments=[way["line"] for way in cluster],
                uses=_osm_uses(tags),
                names=_names(tags),
            ))
    return sorted(routes, key=lambda route: (route.name, route.key))


FORESTRY_NAMES = re.compile(r"林道|林班")
"""Japanese forestry roads (林道) and compartment lines (林班線) that OSM sometimes tags as
paths: a forestry track, not a walk anyone sets out on."""


def _is_named_footpath(tags: Record) -> bool:
    name = (tags.get("name") or "").strip()
    if tags.get("highway") not in ("path", "footway") or not name:
        return False
    if tags.get("footway") in ("sidewalk", "crossing") or FORESTRY_NAMES.search(name):
        return False
    return tags.get("access") not in ("private", "no")


def _osm_line(geometry: list[Record] | None) -> list[Coordinate] | None:
    line = [
        (float(node["lon"]), float(node["lat"]))
        for node in geometry or []
        if node and node.get("lon") is not None and node.get("lat") is not None
    ]
    return line if len(line) >= 2 else None


def _display_name(country: str, tags: Record) -> str | None:
    """English where OSM has it in Japan (as the Japanese build names huts), else the
    name as mapped."""
    keys = ("name:en", "name") if country == "jp" else ("name", "name:en")
    for key in keys:
        if value := " ".join((tags.get(key) or "").split()):
            return value
    return None


def _latin_name(country: str, tags: Record) -> str | None:
    """A Latin-script name to make an identifier from; a Japanese name without one is
    named by its OSM key instead."""
    keys = ("name:en", "name:ja-Latn", "name:ja_rm") if country == "jp" else ("name", "name:en")
    for key in keys:
        if value := (tags.get(key) or "").strip():
            return value
    return None


def _names(tags: Record) -> tuple[str, ...]:
    return tuple(
        value
        for key in ("name", "name:en", "name:ja", "name:no", "name:nb", "name:nn")
        if (value := (tags.get(key) or "").strip())
    )


def _osm_uses(tags: Record) -> str:
    """Who may use the line, read as the US reads OSM for Sequoia: on foot always, and on
    horse or bicycle where the way says so."""
    uses = ["Hike"]
    if tags.get("horse") in ("yes", "designated", "permissive"):
        uses.append("Horse")
    if tags.get("bicycle") in ("yes", "designated", "permissive"):
        uses.append("Bicycle")
    return ", ".join(uses)


def _clusters(ways: list[Record]) -> list[list[Record]]:
    """Ways that lie together, single-linkage within :data:`CLUSTER_REACH_M`, in order of
    their lowest OSM id so the clusters come out the same every run."""
    ways = sorted(ways, key=lambda way: way["id"])
    if len(ways) == 1:
        return [ways]
    latitude = sum(way["line"][0][1] for way in ways) / len(ways)
    scale_x = 111_320.0 * math.cos(math.radians(latitude))
    points = []
    for way in ways:
        stations = [(s.longitude, s.latitude) for s in _stations(way["line"], 100.0)]
        points.append(np.array([(lon * scale_x, lat * 110_574.0) for lon, lat in stations]))
    parent = list(range(len(ways)))

    def find(index: int) -> int:
        while parent[index] != index:
            parent[index] = parent[parent[index]]
            index = parent[index]
        return index

    for first in range(len(ways)):
        for second in range(first + 1, len(ways)):
            if find(first) == find(second):
                continue
            gaps = points[first][:, None, :] - points[second][None, :, :]
            if float(np.sqrt((gaps**2).sum(axis=2)).min()) <= CLUSTER_REACH_M:
                parent[find(second)] = find(first)
    clusters: dict[int, list[Record]] = {}
    for index, way in enumerate(ways):
        clusters.setdefault(find(index), []).append(way)
    return list(clusters.values())


def _stations(line: list[Coordinate], interval_m: float) -> list[measure.Station]:
    return measure.resample(line, interval_m)


# MARK: - Measuring


def measure_park(
    country: str,
    park: Record,
    routes: list[Route],
    model: elevation.CopernicusDEM,
    pois: list[Record],
    registry: ids.Registry,
) -> list[Record]:
    """A park's routes measured into catalogue records, shortest lines dropped."""
    sights = [poi for poi in pois if poi.get("kind") in SIGHT_KINDS and poi.get("location")]
    anchors = [
        (poi["location"]["longitude"], poi["location"]["latitude"])
        for poi in pois
        if poi.get("kind") in TRAILHEAD_KINDS and poi.get("location")
    ]
    records: list[Record] = []
    seen: set[str] = set()
    for route in routes:
        record = trail_record(country, park, route, model.sample, sights, anchors, registry)
        if record is None or record["id"] in seen:
            continue
        seen.add(record["id"])
        records.append(record)
    return records


def trail_record(
    country: str,
    park: Record,
    route: Route,
    sampler: Any,
    sights: list[Record],
    anchors: list[Coordinate],
    registry: ids.Registry,
) -> Record | None:
    """One route measured exactly as ``trail_catalogue`` measures a US trail, in the
    shape it writes to ``trails.json``; ``None`` for a line under 250 m."""
    # A segment with no length (one point digitised twice) has no stations to measure, and
    # would leave the whole trail unmeasured.
    segments = [line for line in route.segments if line_length_m(line) >= 1.0]
    if not segments:
        return None
    digitised = trails.chain([{"coordinates": line} for line in segments])
    ends = {(chain[0], chain[-1]) for chain in digitised}
    chains = trail_catalogue.walking_order(digitised, anchors, sampler)
    total = sum(line_length_m(chain) for chain in chains) or 1.0
    measurements = [
        trail_catalogue.measure_as_walked(
            chain,
            ends,
            sampler,
            profile_points=max(2, round(PROFILE_POINTS * line_length_m(chain) / total)),
        )
        for chain in chains
    ]
    length = sum(item.length_m for item in measurements)
    if length < MIN_LENGTH_M:
        return None
    paths = [
        simplified
        for chain in chains
        if len(simplified := outline.simplify(list(chain), LINE_TOLERANCE_DEGREES)) >= 2
    ]
    record: Record = {
        "id": ids.country_trail_id(
            registry, country, park_slug(park["id"]), route.key, route.latin_name
        ),
        "placeID": park["id"],
        "name": " ".join(route.name.split()),
        "lengthMetres": round(length, 1),
        "paths": [outline.encode(path) for path in paths],
    }
    if len(chains) == 1 and distance_m(chains[0][0], chains[0][-1]) <= 60 and length > 500:
        record["routeType"] = "loop"
    if all(item.has_elevation for item in measurements):
        record |= {
            "gainMetres": round(sum(item.elevation_gain_m or 0 for item in measurements), 1),
            "lossMetres": round(sum(item.elevation_loss_m or 0 for item in measurements), 1),
            "highPointMetres": round(max(item.high_point_m or 0 for item in measurements), 1),
            "lowPointMetres": round(min(item.low_point_m or 0 for item in measurements), 1),
            "profile": trail_catalogue.joined_profile(measurements),
        }
    record["source"] = route.source
    if route.grade:
        record["publishedGrade"] = route.grade
    if route.bikes_allowed:
        record["bikesAllowed"] = True
    if route.uses:
        record["uses"] = route.uses
    for key, value in route.extra.items():
        record.setdefault(key, value)
    if on_route := trail_catalogue._sights_along(chains, sights):
        record["sightIDs"] = on_route
    if found := features(route.names or (route.name,)):
        record["features"] = found
    return record


# MARK: - Features from the name

# The US reads English words (``trail_catalogue._FEATURE_WORDS``). Abroad the trail's own
# name is Norwegian or Japanese, so each language gets its words, read the same way: only
# what the name says it leads to, never what it passes unnamed.

# Norwegian names compound: Vettisfossen, Skagastølstind, Bessvatnet. A word counts when it
# ends in one of these, so a hut called Fossbu is not a waterfall.
_NORWEGIAN_ENDINGS = {
    "waterfall": ("foss", "fossen", "fossane", "fossene"),
    "summit": ("tind", "tinden", "toppen", "piggen", "nuten", "kollen"),
    "lake": ("vatn", "vatnet", "vann", "vannet", "tjern", "tjernet", "tjønn", "tjønna"),
    "glacier": ("breen", "brea", "breane"),
    "canyon": ("juvet", "gjelet", "gjelen"),
    "beach": ("stranda",),
    "cave": ("grotta", "grotte", "hulen"),
}

# Japanese does not separate words, so these are read anywhere in the name. A name ending
# in 山 (yama, mountain) is a summit; 山 inside a word (山道, a mountain road) is not.
_JAPANESE_WORDS = {
    "waterfall": ("滝",),
    "summit": ("岳", "峰", "山頂", "登山道"),
    "lake": ("湖", "沼", "池"),
    "beach": ("浜", "ビーチ", "海水浴場"),
    "canyon": ("峡", "渓谷"),
    "glacier": ("氷河",),
    "cave": ("洞窟", "鍾乳洞", "洞穴", "風穴"),
    "meadow": ("湿原", "草原", "花畑", "原生花園"),
}
_JAPANESE_ROUTE_WORDS = re.compile(r"(登山道|遊歩道|自然歩道|歩道|コース|ルート|線|道)$")

_ORDER = ("waterfall", "summit", "lake", "arch", "beach", "canyon", "glacier", "cave", "meadow")


def features(names: tuple[str, ...] | list[str]) -> list[str]:
    """What a trail's own name says it leads to, in any of its languages."""
    found: set[str] = set()
    for name in names:
        found.update(trail_catalogue._features(name))
        words = [word for word in re.split(r"[\s\-–—/,()]+", name.lower()) if word]
        for feature, endings in _NORWEGIAN_ENDINGS.items():
            if any(word.endswith(ending) for word in words for ending in endings):
                found.add(feature)
        for feature, terms in _JAPANESE_WORDS.items():
            if any(term in name for term in terms):
                found.add(feature)
        stem = _JAPANESE_ROUTE_WORDS.sub("", name.strip())
        if stem.endswith("山") and len(stem) > 1:
            found.add("summit")
    return [feature for feature in _ORDER if feature in found]


# MARK: - Shared helpers


def park_slug(place_id: str) -> str:
    """``no-np-jotunheimen`` → ``jotunheimen``: the stem of the park's trail identifiers."""
    parts = place_id.split("-", 2)
    return parts[2] if len(parts) == 3 else place_id


def _lines(geometry: Record) -> list[list[Coordinate]]:
    kind = geometry.get("type")
    if kind == "LineString":
        raw = [geometry.get("coordinates") or []]
    elif kind == "MultiLineString":
        raw = list(geometry.get("coordinates") or [])
    else:
        return []
    lines = [
        [(float(point[0]), float(point[1])) for point in line if len(point) >= 2] for line in raw
    ]
    return [line for line in lines if len(line) >= 2]


def _outline_box(polygons: list[outline.Polygon]) -> tuple[float, float, float, float] | None:
    return outline.bbox(polygons)


def _inside(
    polygons: list[outline.Polygon],
    box: tuple[float, float, float, float] | None,
    line: list[Coordinate],
) -> bool:
    """Whether a segment is the park's, by the US catalogue's rule: its middle vertex is
    inside the outline, or within :data:`BOUNDARY_BUFFER_DEGREES` of it."""
    if box is None:
        return False
    south, west, north, east = box
    pad = BOUNDARY_BUFFER_DEGREES
    lon, lat = line[len(line) // 2]
    if not (south - pad <= lat <= north + pad and west - pad <= lon <= east + pad):
        return False
    return outline.contains(polygons, lon, lat) or any(
        outline.contains(polygons, lon + dx, lat + dy) for dx in (-pad, pad) for dy in (-pad, pad)
    )


def _search_box(polygons: list[outline.Polygon]) -> BoundingBox | None:
    box = outline.bbox(polygons)
    if box is None:
        return None
    south, west, north, east = box
    pad = BOUNDARY_BUFFER_DEGREES
    return BoundingBox(west=west - pad, south=south - pad, east=east + pad, north=north + pad)


def _box(lines: list[list[Coordinate]]) -> BoundingBox | None:
    points = [point for line in lines for point in line]
    return BoundingBox.around(points) if points else None


def _latest(source: str, park_id: str) -> Path | None:
    suffix = ".geojson" if source == TURRUTEBASEN else ".json"
    directory = rawstore.latest(source, f"{park_id}{suffix}")
    return directory / f"{park_id}{suffix}" if directory else None


def _read_features(source: str, park_id: str) -> list[Record] | None:
    path = _latest(source, park_id)
    if path is None:
        return None
    return json.loads(path.read_text()).get("features") or []


def _read_osm(country: str, park_id: str) -> Record | None:
    path = _latest(OSM_TRAIL_SOURCES[country], park_id)
    return json.loads(path.read_text()) if path else None


def _write_record(
    directory: Path,
    terms: SourceTerms,
    path: Path,
    url: str,
    parameters: Record,
    **extra: Any,
) -> None:
    """Add one park's request and file to the directory's ``source.json``, carrying
    forward what earlier parks wrote there and replacing this file's earlier entry."""
    record = FetchRecord(source=terms, fetched_at=rawstore.utc_now())
    existing = directory / "source.json"
    name = path.relative_to(directory).as_posix()
    if existing.exists():
        payload = json.loads(existing.read_text())
        record.requests = list(payload.get("requests") or [])
        record.files = [entry for entry in payload.get("files") or [] if entry["path"] != name]
    record.add_request(url, parameters, **extra)
    record.add_file(path, root=directory)
    record.write(directory)


def measurement_method() -> Record:
    """The method, as a pack's ``trails.json`` records it next to the numbers."""
    return {
        "lengthBasis": "horizontal (map) length on the WGS84 ellipsoid",
        "stationIntervalMetres": STATION_INTERVAL_M,
        "smoothingWindowMetres": trail_catalogue.SMOOTHING_WINDOW_M,
        "gainThresholdMetres": measure.HYSTERESIS_THRESHOLD_M,
        "profileSampleCount": PROFILE_POINTS,
        "elevationSource": "Copernicus GLO-30 surface model, bilinear",
        "segmentJoinToleranceMetres": trails.JOIN_TOLERANCE_M,
        "lineSources": {
            "kartverket": "Kartverket Turrutebasen (CC BY 4.0, ©Kartverket)",
            "doc": "DOC Tracks (CC BY 4.0, Crown Copyright: Department of Conservation "
            "Te Papa Atawhai)",
            "parksCanada": "Parks Canada trails (Open Government Licence – Canada)",
            "osm": "OpenStreetMap (ODbL), © OpenStreetMap contributors",
        },
    }
