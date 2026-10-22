"""Build the map's other public lands and its transport layers from ``lands_fetch``'s raw.

Adds to the places ``reference_build`` writes:

* every national forest and national grassland (Forest Service, proclaimed boundaries);
* every national wildlife refuge (Fish and Wildlife Service);
* the BLM's national monuments, conservation areas and similar designations;
* every public National Natural Landmark, as a point;
* every National Scenic Byway and All-American Road, as a line.

and writes ``routes.json`` (byway lines) and ``transport.json`` (Interstates, US routes,
Amtrak routes and stations) beside them.

The curated sites in ``content/`` win wherever an id collides — they carry a written
summary and a photograph — and a BLM unit that is also an NPS unit (Craters of the Moon,
Grand Canyon–Parashant) is left to the NPS's record. None of these places gets prose: the
sources publish a name, a designation, a boundary and an area, and that is what ships.
"""

from __future__ import annotations

import json
import re
from collections.abc import Iterable
from itertools import pairwise
from pathlib import Path
from typing import Any

from . import ids, outline

# Outline generalisation, in degrees: about 110 m, as for the other non-park tiers.
LANDS_TOLERANCE = 0.0011
# Line generalisation, in degrees. Interstates at about 200 m, US routes at 300 m: both are
# drawn from regional zoom outwards, where a pixel is several hundred metres. Byways and
# Amtrak at about 100 m, because they are drawn close up as well.
INTERSTATE_TOLERANCE = 0.002
US_HIGHWAY_TOLERANCE = 0.003
RAIL_TOLERANCE = 0.001
BYWAY_TOLERANCE = 0.001

# A state counts as one of a place's states when at least this share of its sample points
# falls inside it. Lower, and a refuge on a state line picks up its neighbour through
# generalisation alone.
STATE_SHARE = 0.05

# BLM units whose published name carries no designation, or carries the wrong one. Keyed by
# NLCS_ID; each value is the name and designation as the unit's establishing act gives them.
BLM_OVERRIDES: dict[str, tuple[str, str]] = {
    "NLCS000855": ("Red Cliffs", "National Conservation Area"),
    "NLCS000854": ("Beaver Dam Wash", "National Conservation Area"),
    "NLCS000853": ("Beaver Dam Wash", "National Conservation Area"),
    "NLCS000856": ("Jurassic", "National Monument"),
    "NLCS000857": ("John Wesley Powell", "National Conservation Area"),
    "NLCS000606": ("Avi Kwa Ame", "National Monument"),
    "NLCS000112": ("Baaj Nwaavjo I'tah Kukveni", "National Monument"),
    "NLCS000052": ("Gila Box Riparian", "National Conservation Area"),
    "NLCS000053": ("Agua Fria", "National Monument"),
    "NLCS000051": ("San Pedro Riparian", "National Conservation Area"),
    "NLCS000057": ("Las Cienegas", "National Conservation Area"),
    "NLCS000055": ("Ironwood Forest", "National Monument"),
    "NLCS000054": ("Grand Canyon-Parashant", "National Monument"),
    "NLCS000056": ("Vermilion Cliffs", "National Monument"),
    "NLCS000058": ("Sonoran Desert", "National Monument"),
    "NLCS000851": ("Bears Ears", "National Monument"),
    "NLCS000852": ("Grand Staircase-Escalante", "National Monument"),
    "NLCS000602": ("Black Rock Desert-High Rock Canyon", "National Conservation Area"),
    "NLCS000402": ("Morley Nelson Snake River Birds of Prey", "National Conservation Area"),
    "NLCS000323": ("Dominguez-Escalante", "National Conservation Area"),
    "NLCS000522": ("Fort Stanton-Snowy River Cave", "National Conservation Area"),
    "NLCS000733": ("Steens Mountain", "Cooperative Management and Protection Area"),
}

# What the BLM's own management codes mean, for a unit whose name does not say.
BLM_CODES = {
    "BLM_NM": "National Monument",
    "BLM_MON": "National Monument",
    "BLM_NCA": "National Conservation Area",
    "BLM_NA": "Outstanding Natural Area",
    "BLM_ONA": "Outstanding Natural Area",
    "BLM_NSA": "National Scenic Area",
    "BLM_FR": "Forest Reserve",
    "BLM_CMPA": "Cooperative Management and Protection Area",
}

# Designations a BLM unit's name can end in, longest first so "National Volcanic
# Monument" is not read as "Monument".
BLM_SUFFIXES = (
    "Cooperative Management and Protection Area",
    "Outstanding Natural Area",
    "National Conservation Area",
    "National Scenic Area",
    "National Monument",
    "Forest Reserve",
)

# A unit in the BLM's layer that no source names with a designation, and that this build
# cannot confirm one for, is still a unit of the National Conservation Lands.
BLM_FALLBACK_DESIGNATION = "National Conservation Lands"

# Amtrak's dataset spells one service "Lincol". Nothing else is renamed.
AMTRAK_RENAMES = {"Lincol Service Missouri River Runner": "Lincoln Service Missouri River Runner"}


def build(
    raw_lands: Path,
    places: list[dict[str, Any]],
    boundaries: dict[str, Any],
) -> dict[str, Any]:
    """Append the other public lands to ``places`` and ``boundaries``; return the byway
    routes, keyed by place id."""
    states = _States(raw_lands / "states.geojson")
    taken = {place["id"] for place in places}
    nps_names = {
        _name_key(place["name"]) for place in places if place.get("agency") == "nps"
    }
    routes: dict[str, Any] = {}
    added: dict[str, int] = {}

    def add(place: dict[str, Any], outline_entry: dict[str, Any] | None) -> None:
        if place["id"] in taken:
            return
        taken.add(place["id"])
        places.append(place)
        if outline_entry:
            boundaries[place["id"]] = outline_entry
        added[place["kind"]] = added.get(place["kind"], 0) + 1

    for place, entry in _forests(raw_lands / "forests.geojson", states):
        add(place, entry)
    for place, entry in _grasslands(raw_lands / "grasslands.geojson", states):
        add(place, entry)
    for place, entry in _refuges(raw_lands / "refuges.geojson", states):
        add(place, entry)
    for place, entry in _blm(raw_lands / "blm-nlcs.geojson", states, nps_names):
        add(place, entry)
    for place in _landmarks(raw_lands / "landmarks.geojson", states):
        add(place, None)
    for place, route in _byways(raw_lands / "byways.geojson"):
        if place["id"] not in taken:
            routes[place["id"]] = route
        add(place, None)

    print(f"    other public lands: {added}")
    return routes


# MARK: - Polygon lands


def _forests(path: Path, states: _States) -> Iterable[tuple[dict[str, Any], dict[str, Any]]]:
    yield from _polygon_lands(
        path,
        states,
        name_field="forest_grasslandname",
        suffix="National Forest",
        prefix="nf",
        kind="nationalForest",
        agency="forestService",
        acres_field="gis_acres",
    )


def _grasslands(path: Path, states: _States) -> Iterable[tuple[dict[str, Any], dict[str, Any]]]:
    yield from _polygon_lands(
        path,
        states,
        name_field="grasslandname",
        suffix="National Grassland",
        prefix="ng",
        kind="nationalGrassland",
        agency="forestService",
        acres_field="gis_acres",
    )


def _polygon_lands(
    path: Path,
    states: _States,
    *,
    name_field: str,
    suffix: str,
    prefix: str,
    kind: str,
    agency: str,
    acres_field: str,
) -> Iterable[tuple[dict[str, Any], dict[str, Any]]]:
    grouped: dict[str, tuple[list[outline.Polygon], float]] = {}
    for feature in _features(path):
        properties = feature.get("properties") or {}
        full = (properties.get(name_field) or "").strip()
        if not full:
            continue
        polygons, acres = grouped.get(full, ([], 0.0))
        polygons.extend(outline.polygons_of(feature.get("geometry")))
        grouped[full] = (polygons, acres + float(properties.get(acres_field) or 0))
    for full, (polygons, acres) in sorted(grouped.items()):
        name = _strip_suffix(full, suffix)
        place = _polygon_place(
            place_id=f"{prefix}-{ids.slug(name)}",
            name=name,
            designation=suffix,
            kind=kind,
            agency=agency,
            polygons=polygons,
            acres=acres,
            states=states,
        )
        if place:
            yield place


def _refuges(path: Path, states: _States) -> Iterable[tuple[dict[str, Any], dict[str, Any]]]:
    grouped: dict[str, list[outline.Polygon]] = {}
    for feature in _features(path):
        name = ((feature.get("properties") or {}).get("ORGNAME") or "").strip()
        if name and not REFUGE_EXCLUDED.search(name):
            grouped.setdefault(name, []).extend(outline.polygons_of(feature.get("geometry")))
    for full, polygons in sorted(grouped.items()):
        name, designation = _refuge_name(full)
        place = _polygon_place(
            place_id=f"nwr-{ids.slug(name)}",
            name=name,
            designation=designation,
            kind="wildlifeRefuge",
            agency="fishAndWildlife",
            polygons=polygons,
            acres=None,
            states=states,
        )
        if place:
            yield place


# The designations a refuge's name can end in, longest first so "National Fish and
# Wildlife Refuge" is not read as "Wildlife Refuge".
REFUGE_SUFFIXES = (
    "National Wildlife Refuge and Conservation Area",
    "National Fish and Wildlife Refuge",
    "National Wildlife and Fish Refuge",
    "International Wildlife Refuge",
    "Migratory Bird Refuge",
    "National Antelope Refuge",
    "National Game Preserve",
    "Wildlife Management Area",
    "National Wildlife Refuge",
    "Research Refuge",
    "Wildlife Refuge",
    "Refuge",
)

# Records in the refuge layer that are offices rather than places to visit.
REFUGE_EXCLUDED = re.compile(r"administrative site", re.IGNORECASE)


def _refuge_name(upper: str) -> tuple[str, str]:
    """``("Bosque del Apache", "National Wildlife Refuge")`` from the FWS's capitals.

    Two refuges carry words after the designation — "John Heinz National Wildlife Refuge
    at Tinicum", "Julia Butler Hansen Refuge for the Columbian White Tail Deer" — and keep
    them in the designation, where the FWS puts them.
    """
    text = title_case(upper)
    for suffix in REFUGE_SUFFIXES:
        match = re.search(rf"\s+({re.escape(suffix)})(\s+(?:at|for)\s.*)?$", text, re.IGNORECASE)
        if match:
            trailing = match.group(2) or ""
            purpose = trailing.split()[:1] == ["for"]
            name = text[: match.start()].strip()
            if trailing and not purpose:
                name = f"{name}{trailing}"
            return name, suffix + (trailing if purpose else "")
    return text, "National Wildlife Refuge"


def _blm(
    path: Path, states: _States, nps_names: set[str]
) -> Iterable[tuple[dict[str, Any], dict[str, Any]]]:
    grouped: dict[str, tuple[str, list[outline.Polygon]]] = {}
    for feature in _features(path):
        properties = feature.get("properties") or {}
        name, designation = _blm_name(properties)
        if not name:
            continue
        _, polygons = grouped.get(name, (designation, []))
        polygons.extend(outline.polygons_of(feature.get("geometry")))
        grouped[name] = (designation, polygons)
    for name, (designation, polygons) in sorted(grouped.items()):
        if _name_key(name) in nps_names:
            continue
        is_monument = "Monument" in designation
        prefix = "nm" if is_monument else "nca"
        place = _polygon_place(
            place_id=f"{prefix}-{ids.slug(name)}",
            name=name,
            designation=designation,
            kind="blmMonument" if is_monument else "blmConservationArea",
            agency="blm",
            polygons=polygons,
            acres=None,
            states=states,
        )
        if place:
            yield place


def _blm_name(properties: dict[str, Any]) -> tuple[str | None, str]:
    nlcs_id = properties.get("NLCS_ID") or ""
    if nlcs_id in BLM_OVERRIDES:
        return BLM_OVERRIDES[nlcs_id]
    raw = (properties.get("NCA_NAME") or properties.get("Label") or "").strip()
    if not raw:
        return None, ""
    if raw.isupper():
        raw = title_case(raw)
    raw = re.sub(r"\s*[-/]\s*", "-", raw)
    for suffix in BLM_SUFFIXES:
        if raw.lower().endswith(suffix.lower()):
            return raw[: -len(suffix)].strip(" -"), suffix
    code = properties.get("sma_code") or ""
    return raw.strip(" -"), BLM_CODES.get(code, BLM_FALLBACK_DESIGNATION)


def _polygon_place(
    *,
    place_id: str,
    name: str,
    designation: str,
    kind: str,
    agency: str,
    polygons: list[outline.Polygon],
    acres: float | None,
    states: _States,
) -> tuple[dict[str, Any], dict[str, Any]] | None:
    polygons = _one_side_of_the_antimeridian(polygons)
    simplified = outline.generalise(polygons, LANDS_TOLERANCE)
    box = outline.bbox(simplified)
    if not simplified or box is None:
        return None
    entry = {
        "bbox": [round(value, 5) for value in box],
        "polygons": [[outline.encode(ring) for ring in polygon] for polygon in simplified],
    }
    latitude, longitude = outline.label_point(simplified) or (0.0, 0.0)
    south, west, north, east = entry["bbox"]
    place: dict[str, Any] = {
        "id": place_id,
        "name": name,
        "designation": designation,
        "kind": kind,
        "agency": agency,
        "states": states.of_polygons(simplified, (latitude, longitude)),
        "centre": {"latitude": round(latitude, 5), "longitude": round(longitude, 5)},
        "extent": {"south": south, "west": west, "north": north, "east": east},
        "facts": {"areaAcres": round(acres)} if acres else {},
    }
    return place, entry


def _one_side_of_the_antimeridian(polygons: list[outline.Polygon]) -> list[outline.Polygon]:
    """Drop the smaller side of a place that straddles 180°.

    Only the Alaska Maritime refuge does: a few of the Near Islands lie in the eastern
    hemisphere. The app's outlines and framing are planar in longitude, and a box from
    172° E to 130° W would frame the whole Pacific.
    """
    east = [p for p in polygons if p and p[0] and p[0][0][0] > 0]
    west = [p for p in polygons if p and p[0] and p[0][0][0] <= 0]
    if not east or not west:
        return polygons
    near_line = all(abs(p[0][0][0]) > 150 for p in east + west if p[0][0][0] > 0)
    if not near_line:
        return polygons
    area = sum(outline.ring_area(p[0]) for p in east), sum(outline.ring_area(p[0]) for p in west)
    return west if area[1] >= area[0] else east


# MARK: - Points and lines


def _landmarks(path: Path, states: _States) -> Iterable[dict[str, Any]]:
    seen: set[str] = set()
    for feature in sorted(
        _features(path), key=lambda f: (f.get("properties") or {}).get("NNL_Name") or ""
    ):
        properties = feature.get("properties") or {}
        name = (properties.get("NNL_Name") or "").strip()
        geometry = feature.get("geometry") or {}
        if not name or geometry.get("type") != "Point":
            continue
        longitude, latitude = geometry["coordinates"][:2]
        codes = [c.strip().upper() for c in re.split(r"[|,/]", properties.get("State") or "")]
        codes = [code for code in codes if len(code) == 2]
        if not codes:
            codes = states.of_points([(latitude, longitude)])
        place_id = f"nnl-{ids.slug(name)}"
        if place_id in seen:
            place_id = f"{place_id}-{codes[0].lower()}" if codes else place_id
        seen.add(place_id)
        acres = properties.get("Acre_Calc")
        yield {
            "id": place_id,
            "name": name,
            "designation": "National Natural Landmark",
            "kind": "naturalLandmark",
            "agency": "other",
            "states": codes,
            "centre": {"latitude": round(latitude, 5), "longitude": round(longitude, 5)},
            "facts": {"areaAcres": round(float(acres))} if acres else {},
        }


def _byways(path: Path) -> Iterable[tuple[dict[str, Any], dict[str, Any]]]:
    """One place per byway, joining the per-state pieces the FHWA publishes."""
    grouped: dict[str, dict[str, Any]] = {}
    for feature in _features(path):
        properties = feature.get("properties") or {}
        raw = (properties.get("NAME") or "").strip()
        if not raw:
            continue
        name = re.sub(r"\s+-\s+[A-Z]{2}(?:/[A-Z]{2})*$", "", raw).strip()
        entry = grouped.setdefault(
            name, {"states": [], "lines": [], "aar": False, "years": []}
        )
        state = (properties.get("STATE") or "").strip().upper()
        for code in re.split(r"[/,]", state):
            if len(code.strip()) == 2 and code.strip() not in entry["states"]:
                entry["states"].append(code.strip())
        entry["aar"] |= (properties.get("Current_Desig") or "") == "AAR"
        for field in ("NSB_Year", "AAR_Year"):
            value = (properties.get(field) or "").strip()
            if value.isdigit():
                entry["years"].append(int(value))
        entry["lines"].extend(_lines_of(feature.get("geometry")))
    for name, entry in sorted(grouped.items()):
        paths = [
            path
            for path in (outline.simplify(line, BYWAY_TOLERANCE) for line in _chain(entry["lines"]))
            if len(path) >= 2
        ]
        if not paths:
            continue
        route = _route_entry(name, paths)
        middle = _midpoint(max(paths, key=_path_length))
        place: dict[str, Any] = {
            "id": f"byway-{ids.slug(name)}",
            "name": name,
            "designation": "All-American Road" if entry["aar"] else "National Scenic Byway",
            "kind": "scenicByway",
            "agency": "other",
            "states": entry["states"],
            "centre": {"latitude": round(middle[1], 5), "longitude": round(middle[0], 5)},
            "extent": dict(zip(("south", "west", "north", "east"), route["bbox"], strict=True)),
            "facts": {"establishedYear": min(entry["years"])} if entry["years"] else {},
        }
        yield place, route


# MARK: - Transport


def build_transport(raw_transport: Path) -> dict[str, Any]:
    interstates = _numbered_routes(
        raw_transport / "interstates.geojson", "I-{}", INTERSTATE_TOLERANCE
    )
    highways = _numbered_routes(
        raw_transport / "us-highways.geojson", "US {}", US_HIGHWAY_TOLERANCE
    )
    amtrak: dict[str, list[list[tuple[float, float]]]] = {}
    for feature in _features(raw_transport / "amtrak-routes.geojson"):
        name = ((feature.get("properties") or {}).get("name") or "").strip()
        if name:
            name = AMTRAK_RENAMES.get(name, name)
            amtrak.setdefault(name, []).extend(_lines_of(feature.get("geometry")))
    amtrak_routes = [
        _route_entry(name, paths)
        for name, lines in sorted(amtrak.items())
        if (paths := _generalised(lines, RAIL_TOLERANCE))
    ]
    stations = []
    seen: set[str] = set()
    for feature in _features(raw_transport / "amtrak-stations.geojson"):
        properties = feature.get("properties") or {}
        geometry = feature.get("geometry") or {}
        code = (properties.get("Code") or "").strip().upper()
        if not code or code in seen or geometry.get("type") != "Point":
            continue
        seen.add(code)
        longitude, latitude = geometry["coordinates"][:2]
        station: dict[str, Any] = {
            "code": code,
            "name": (properties.get("StationName") or properties.get("City") or code).strip(),
            "location": {"latitude": round(latitude, 5), "longitude": round(longitude, 5)},
        }
        if city := (properties.get("City") or "").strip():
            station["city"] = city
        if state := (properties.get("State") or "").strip().upper():
            station["state"] = state
        stations.append(station)
    stations.sort(key=lambda s: s["code"])
    print(
        f"    transport: {len(interstates)} Interstates, {len(highways)} US routes, "
        f"{len(amtrak_routes)} Amtrak routes, {len(stations)} stations"
    )
    return {
        "interstates": interstates,
        "usHighways": highways,
        "amtrakRoutes": amtrak_routes,
        "amtrakStations": stations,
    }


def _numbered_routes(path: Path, label: str, tolerance: float) -> list[dict[str, Any]]:
    grouped: dict[str, list[list[tuple[float, float]]]] = {}
    for feature in _features(path):
        number = str((feature.get("properties") or {}).get("SIGNN1") or "").strip()
        if number:
            grouped.setdefault(number, []).extend(_lines_of(feature.get("geometry")))
    result = []
    for number in sorted(grouped, key=_route_sort_key):
        paths = _generalised(grouped[number], tolerance)
        if paths:
            result.append(_route_entry(label.format(number), paths))
    return result


def _route_sort_key(number: str) -> tuple[int, str]:
    digits = re.match(r"\d+", number)
    return (int(digits.group()) if digits else 10_000, number)


def _generalised(
    lines: list[list[tuple[float, float]]], tolerance: float
) -> list[list[tuple[float, float]]]:
    paths = []
    for line in _chain(lines):
        simplified = outline.simplify(line, tolerance)
        if len(simplified) >= 2 and _path_length(simplified) > tolerance * 2:
            paths.append(simplified)
    return paths


def _chain(lines: list[list[tuple[float, float]]]) -> list[list[tuple[float, float]]]:
    """Join pieces that meet end to end into as few paths as possible.

    The sources publish a route as hundreds of short segments, one per section of road.
    Joined, each path generalises as a whole and encodes once, which is most of the size
    saving; a real gap — a ferry, a missing section — stays a gap.
    """
    def key(point: tuple[float, float]) -> tuple[int, int]:
        return (round(point[0] * 1e4), round(point[1] * 1e4))

    pieces = [line for line in lines if len(line) >= 2]
    ends: dict[tuple[int, int], list[int]] = {}
    for index, line in enumerate(pieces):
        ends.setdefault(key(line[0]), []).append(index)
        ends.setdefault(key(line[-1]), []).append(index)
    used = [False] * len(pieces)

    def take(at: tuple[int, int]) -> list[tuple[float, float]] | None:
        for index in ends.get(at, []):
            if not used[index]:
                used[index] = True
                line = pieces[index]
                return line if key(line[0]) == at else list(reversed(line))
        return None

    # Start from dead ends and junctions, so a path runs between them rather than from
    # the middle of a road.
    order = sorted(
        range(len(pieces)),
        key=lambda i: min(len(ends[key(pieces[i][0])]), len(ends[key(pieces[i][-1])])) != 1,
    )
    paths = []
    for start in order:
        if used[start]:
            continue
        used[start] = True
        path = list(pieces[start])
        while (following := take(key(path[-1]))) is not None:
            path.extend(following[1:])
        while (preceding := take(key(path[0]))) is not None:
            path[:0] = list(reversed(preceding))[:-1]
        paths.append(path)
    return paths


def _lines_of(geometry: dict[str, Any] | None) -> list[list[tuple[float, float]]]:
    if not geometry:
        return []
    kind = geometry.get("type")
    coordinates = geometry.get("coordinates") or []
    if kind == "LineString":
        lines = [coordinates]
    elif kind == "MultiLineString":
        lines = coordinates
    else:
        return []
    return [[(float(p[0]), float(p[1])) for p in line] for line in lines if len(line) >= 2]


def _route_entry(name: str, paths: list[list[tuple[float, float]]]) -> dict[str, Any]:
    points = [point for path in paths for point in path]
    lons = [lon for lon, _ in points]
    lats = [lat for _, lat in points]
    return {
        "name": name,
        "bbox": [
            round(min(lats), 5), round(min(lons), 5), round(max(lats), 5), round(max(lons), 5)
        ],
        "paths": [outline.encode(path) for path in paths],
    }


def _path_length(path: list[tuple[float, float]]) -> float:
    return sum(
        ((x2 - x1) ** 2 + (y2 - y1) ** 2) ** 0.5
        for (x1, y1), (x2, y2) in pairwise(path)
    )


def _midpoint(path: list[tuple[float, float]]) -> tuple[float, float]:
    half = _path_length(path) / 2
    walked = 0.0
    for (x1, y1), (x2, y2) in pairwise(path):
        leg = ((x2 - x1) ** 2 + (y2 - y1) ** 2) ** 0.5
        if walked + leg >= half and leg > 0:
            t = (half - walked) / leg
            return (x1 + (x2 - x1) * t, y1 + (y2 - y1) * t)
        walked += leg
    return path[len(path) // 2]


# MARK: - States


class _States:
    """Which states a place lies in, by point in polygon against the Census outlines."""

    def __init__(self, path: Path) -> None:
        self._states: list[tuple[str, list[outline.Polygon], tuple[float, ...]]] = []
        for feature in _features(path):
            code = ((feature.get("properties") or {}).get("STUSAB") or "").upper()
            polygons = outline.polygons_of(feature.get("geometry"))
            box = outline.bbox(polygons)
            if code and polygons and box:
                self._states.append((code, polygons, box))

    def at(self, latitude: float, longitude: float) -> str | None:
        for code, polygons, (south, west, north, east) in self._states:
            inside_box = south <= latitude <= north and west <= longitude <= east
            if inside_box and outline.contains(polygons, longitude, latitude):
                return code
        return None

    def of_points(self, points: list[tuple[float, float]]) -> list[str]:
        counts: dict[str, int] = {}
        for latitude, longitude in points:
            if code := self.at(latitude, longitude):
                counts[code] = counts.get(code, 0) + 1
        return sorted(counts, key=lambda code: -counts[code])

    def of_polygons(
        self, polygons: list[outline.Polygon], label: tuple[float, float]
    ) -> list[str]:
        """Every state holding a real share of the place, largest share first.

        Shares are by area: a grid of points over the place, kept where they fall inside
        it. A place too small or too scattered for the grid to land in — a refuge of a
        hundred island parcels — is sampled along its outlines instead. One with no point
        in any state, a remote Pacific atoll, has none.
        """
        box = outline.bbox(polygons)
        samples: list[tuple[float, float]] = []
        if box is not None:
            south, west, north, east = box
            steps = 28
            for row in range(steps):
                latitude = south + (north - south) * (row + 0.5) / steps
                for column in range(steps):
                    longitude = west + (east - west) * (column + 0.5) / steps
                    if outline.contains(polygons, longitude, latitude):
                        samples.append((latitude, longitude))
        if len(samples) < 20:
            vertices = [point for polygon in polygons for point in polygon[0]]
            step = max(1, len(vertices) // 240)
            samples = [(lat, lon) for lon, lat in vertices[::step]] + [label]
        counts: dict[str, int] = {}
        for latitude, longitude in samples:
            if code := self.at(latitude, longitude):
                counts[code] = counts.get(code, 0) + 1
        total = max(1, len(samples))
        ordered = sorted(counts, key=lambda code: -counts[code])
        kept = [code for code in ordered if counts[code] / total >= STATE_SHARE]
        return kept or ordered[:1]


# MARK: - Names


_SMALL_WORDS = frozenset({
    "a", "an", "and", "at", "by", "de", "del", "des", "du", "el", "for", "in", "la", "las",
    "le", "los", "of", "on", "the", "to", "y",
})


def title_case(text: str) -> str:
    """Title case for names the sources publish in capitals.

    ``J. N. DING DARLING`` → ``J. N. Ding Darling``; ``MCKAY CREEK`` → ``McKay Creek``;
    ``BOSQUE DEL APACHE`` → ``Bosque del Apache``; ``D'ARBONNE`` → ``D'Arbonne``.
    """
    words = re.split(r"(\s+|-)", text.strip().lower())
    result = []
    first = True
    for word in words:
        if not word or word.isspace() or word == "-":
            result.append(word)
            continue
        if not first and word in _SMALL_WORDS:
            result.append(word)
        else:
            result.append(_capitalise(word))
        first = False
    return "".join(result)


def _capitalise(word: str) -> str:
    if re.fullmatch(r"[ivx]+", word) and len(word) <= 4:
        return word.upper()
    if word.startswith("mc") and len(word) > 2:
        return "Mc" + word[2:].capitalize()
    if "'" in word or "’" in word:
        head, _, tail = word.replace("’", "'").partition("'")
        if len(head) == 1 and tail:
            return head.upper() + "'" + tail.capitalize()
        return head.capitalize() + "'" + tail
    if re.fullmatch(r"[a-z]\.", word):
        return word.upper()
    return word[:1].upper() + word[1:]


def _strip_suffix(name: str, suffix: str) -> str:
    if name.lower().endswith(suffix.lower()):
        return name[: -len(suffix)].strip()
    return name


def _name_key(name: str) -> str:
    return ids.slug(name)


def _features(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        print(f"    missing {path.name}: run `unigrids-pipeline reference` with network")
        return []
    return json.loads(path.read_text()).get("features") or []
