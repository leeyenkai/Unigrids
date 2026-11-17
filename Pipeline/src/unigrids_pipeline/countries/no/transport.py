"""Norway's rail layers and huts, from the Overpass answers in ``raw/<date>/no-osm/``.

``railLines`` is every passenger route (``route=train``) that stops in Norway, the
relations of one ``ref`` drawn as one line — "F4 Oslo S–Bergen" is several relations, one
per direction and variant. ``railStations`` is every station within 100 km of a national
park, with the lines that stop there: a line stops at a station when the station, or the
stop area it belongs to, is one of the route's members, or one of the route's stops lies
within ``LINK_METRES`` of it.

Shipping OSM geometry as data makes these layers a Derivative Database under the ODbL:
they carry OpenStreetMap's attribution and stay available under the same licence.
"""

from __future__ import annotations

import json
import math
import re
from collections.abc import Callable, Iterable
from itertools import pairwise
from pathlib import Path
from typing import Any

from ... import outline

# Rail lines are drawn as the US draws Amtrak's (``lands_build.RAIL_TOLERANCE``).
RAIL_TOLERANCE = 0.001
LINK_METRES = 400.0
STATION_REACH_KM = 100.0

# Stations of other kinds of railway, which the rail layer is not about.
_OTHER_RAILWAYS = frozenset({"subway", "light_rail", "tram", "monorail", "funicular", "miniature"})
# A route's stopping places: "stop", "platform", their entry- and exit-only forms, and the
# older "forward_stop"; a node with no role is a stop on routes mapped the old way.
_STOP_ROLE = re.compile(r"stop|platform|^$")
_ARROWS = re.compile(r"\s*(?:=>|->|→|⇒)\s*")

Point = tuple[float, float]
"""``(latitude, longitude)``."""


# MARK: - Elements


def point_of(element: dict[str, Any]) -> Point | None:
    if "lat" in element and "lon" in element:
        return float(element["lat"]), float(element["lon"])
    centre = element.get("center") or {}
    if "lat" in centre and "lon" in centre:
        return float(centre["lat"]), float(centre["lon"])
    return None


def key_of(element: dict[str, Any]) -> str:
    """``osm:node/123``: the registry key, and the station code."""
    return f"osm:{element['type']}/{element['id']}"


def huts(payload: dict[str, Any]) -> list[dict[str, Any]]:
    """The named huts in a park's answer: ``tourism=alpine_hut|wilderness_hut``."""
    found = []
    for element in payload.get("elements") or []:
        tags = element.get("tags") or {}
        is_hut = tags.get("tourism") in ("alpine_hut", "wilderness_hut")
        if is_hut and (tags.get("name") or "").strip() and point_of(element) is not None:
            found.append(element)
    return found


# Tags that say a station is not one a train calls at today: closed, kept by a museum
# railway, or only planned.
_NOT_IN_SERVICE = ("end_date", "proposed:railway", "construction:railway", "disused:railway",
                   "abandoned:railway", "proposed", "construction")


def is_station(element: dict[str, Any]) -> bool:
    tags = element.get("tags") or {}
    if tags.get("station") in _OTHER_RAILWAYS or tags.get("disused") == "yes":
        return False
    if tags.get("railway:preserved") == "yes" or any(key in tags for key in _NOT_IN_SERVICE):
        return False
    railway = tags.get("railway")
    return railway in ("station", "halt") or (
        tags.get("public_transport") == "station" and tags.get("train") == "yes"
    )


def stations(payloads: Iterable[dict[str, Any]]) -> list[dict[str, Any]]:
    """Every named railway station or halt in the answers, once each. A station mapped
    twice (a node and the area around it, with one name) is kept once, as the node."""
    found: dict[str, dict[str, Any]] = {}
    for payload in payloads:
        for element in payload.get("elements") or []:
            if element.get("type") == "relation" or not is_station(element):
                continue
            if not (element.get("tags") or {}).get("name") or point_of(element) is None:
                continue
            found.setdefault(key_of(element), element)
    ordered = sorted(found.values(), key=lambda e: (e["type"] != "node", e["type"], e["id"]))
    kept: list[dict[str, Any]] = []
    for element in ordered:
        name = element["tags"]["name"].strip().lower()
        here = point_of(element)
        assert here is not None
        duplicate = any(
            other["tags"]["name"].strip().lower() == name
            and metres(here, point_of(other) or here) < LINK_METRES
            for other in kept
        )
        if not duplicate:
            kept.append(element)
    return sorted(kept, key=key_of)


def stop_areas(payloads: Iterable[dict[str, Any]]) -> dict[str, set[str]]:
    """Each element's stop areas, as the members they share: ``osm:node/1`` → every
    member of every stop area it belongs to."""
    shared: dict[str, set[str]] = {}
    for payload in payloads:
        for element in payload.get("elements") or []:
            tags = element.get("tags") or {}
            if element.get("type") != "relation" or tags.get("public_transport") != "stop_area":
                continue
            members = {
                f"osm:{member['type']}/{member['ref']}" for member in element.get("members") or []
            }
            for member in members:
                shared.setdefault(member, set()).update(members)
    return shared


# MARK: - Routes


class Route:
    """One ``route=train`` relation: its tags, its track and its stops."""

    def __init__(self, relation: dict[str, Any]) -> None:
        self.id: int = relation["id"]
        self.tags: dict[str, str] = relation.get("tags") or {}
        self.ways: dict[int, list[tuple[float, float]]] = {}
        self.members: set[str] = set()
        self.stops: list[Point] = []
        for member in relation.get("members") or []:
            role = member.get("role") or ""
            self.members.add(f"osm:{member.get('type')}/{member.get('ref')}")
            if member.get("type") == "way" and not role.startswith("platform"):
                line = [
                    (float(point["lon"]), float(point["lat"]))
                    for point in member.get("geometry") or []
                    if point and "lat" in point and "lon" in point
                ]
                if len(line) >= 2:
                    self.ways[member["ref"]] = line
            elif member.get("type") == "node" and _STOP_ROLE.search(role):
                if "lat" in member and "lon" in member:
                    self.stops.append((float(member["lat"]), float(member["lon"])))

    @property
    def length(self) -> float:
        return sum(_planar_length(line) for line in self.ways.values())

    @property
    def ref(self) -> str:
        """The line's public number — "F4", "R10", "L2x" — without spacing ("R 65") or a
        second operator's number ("F1;70")."""
        return (self.tags.get("ref") or "").split(";")[0].replace(" ", "").strip()

    @property
    def carries_passengers(self) -> bool:
        """``route=train`` is for passengers, but an ore line is sometimes mapped as one."""
        return self.tags.get("service") not in ("industrial", "freight")

    @property
    def group(self) -> str | None:
        if self.ref:
            return self.ref.upper()
        name = clean_name(self.tags.get("name"))
        return name.lower() if name else None

    def stops_in(self, inside: Callable[[float, float], bool]) -> bool:
        """Whether the route stops anywhere ``inside`` says yes to; a route that lists no
        stops is judged by its track instead."""
        if self.stops:
            return any(inside(latitude, longitude) for latitude, longitude in self.stops)
        for line in self.ways.values():
            if any(inside(lat, lon) for lon, lat in line[:: max(1, len(line) // 10)]):
                return True
        return False


def read_routes(directory: Path) -> dict[int, Route]:
    """Every route relation in the tiled answers, once each."""
    routes: dict[int, Route] = {}
    for path in sorted(directory.glob("rail-routes-*.json")):
        for element in json.loads(path.read_text()).get("elements") or []:
            if element.get("type") == "relation" and (element.get("tags") or {}).get(
                "route"
            ) == "train":
                routes.setdefault(element["id"], Route(element))
    return routes


def clean_name(name: str | None) -> str:
    """``"R12 Eidsvoll → Kongsberg"`` → ``"R12 Eidsvoll–Kongsberg"``."""
    return re.sub(r"\s+", " ", _ARROWS.sub("–", name or "")).strip()


def line_name(routes: list[Route]) -> str:
    """One name for the relations of a line: its number and the ends of its longest
    variant ("F4 Oslo S–Bergen"), or the relation's own name where it gives no ends."""
    longest = max(routes, key=lambda route: (route.length, -route.id))
    ref, tags = longest.ref, longest.tags
    origin, destination = (tags.get("from") or "").strip(), (tags.get("to") or "").strip()
    name = clean_name(tags.get("name"))
    if ref and origin and destination:
        return f"{ref} {origin}–{destination}"
    if ref and name:
        squashed = name.upper().replace(" ", "")
        return name if squashed.startswith(ref.upper()) else f"{ref} {name}"
    return ref or name


def build_lines(
    routes: dict[int, Route], in_norway: Callable[[float, float], bool]
) -> tuple[list[dict[str, Any]], dict[int, str]]:
    """``railLines``, and the line each kept route belongs to."""
    groups: dict[str, list[Route]] = {}
    for route in routes.values():
        if route.group and route.ways and route.carries_passengers and route.stops_in(in_norway):
            groups.setdefault(route.group, []).append(route)
    lines: list[dict[str, Any]] = []
    belongs: dict[int, str] = {}
    for group in sorted(groups):
        members = groups[group]
        name = line_name(members)
        ways: dict[int, list[tuple[float, float]]] = {}
        for route in members:
            ways.update(route.ways)
        paths = generalised(list(ways.values()), RAIL_TOLERANCE)
        if not paths or not name:
            continue
        lines.append(route_entry(name, paths))
        for route in members:
            belongs[route.id] = name
    return sorted(lines, key=lambda line: line["name"]), belongs


def station_lines(
    station: dict[str, Any],
    routes: dict[int, Route],
    belongs: dict[int, str],
    areas: dict[str, set[str]],
) -> list[str]:
    """The lines that stop at a station."""
    key = key_of(station)
    here = point_of(station)
    related = areas.get(key, set()) | {key}
    names: set[str] = set()
    for route_id, name in belongs.items():
        route = routes[route_id]
        if related & route.members or (
            here is not None and any(metres(here, stop) <= LINK_METRES for stop in route.stops)
        ):
            names.add(name)
    return sorted(names)


def station_entry(station: dict[str, Any], lines: list[str]) -> dict[str, Any]:
    latitude, longitude = point_of(station) or (0.0, 0.0)
    return {
        "code": key_of(station),
        "name": station["tags"]["name"].strip(),
        "location": {"latitude": round(latitude, 5), "longitude": round(longitude, 5)},
        "country": "NO",
        "lines": lines,
    }


# MARK: - Geometry


def metres(a: Point, b: Point) -> float:
    """Distance on a local flat Earth: right to a few metres at the scale it is used."""
    latitude = math.radians((a[0] + b[0]) / 2)
    dy = (a[0] - b[0]) * 111_195.0
    dx = (a[1] - b[1]) * 111_195.0 * math.cos(latitude)
    return math.hypot(dx, dy)


def distance_to_outline_km(point: Point, polygons: list[outline.Polygon]) -> float:
    """How far a point lies from a place: zero inside it, otherwise to the nearest edge."""
    latitude, longitude = point
    if outline.contains(polygons, longitude, latitude):
        return 0.0
    scale = math.cos(math.radians(latitude))
    best = math.inf
    for polygon in polygons:
        for ring in polygon:
            for (x1, y1), (x2, y2) in zip(ring, ring[1:] + ring[:1], strict=True):
                ax, ay = (x1 - longitude) * scale, y1 - latitude
                bx, by = (x2 - longitude) * scale, y2 - latitude
                dx, dy = bx - ax, by - ay
                length = dx * dx + dy * dy
                t = 0.0 if length == 0 else max(0.0, min(1.0, -(ax * dx + ay * dy) / length))
                best = min(best, math.hypot(ax + t * dx, ay + t * dy))
    return best * 111.195


def generalised(
    lines: list[list[tuple[float, float]]], tolerance: float
) -> list[list[tuple[float, float]]]:
    paths = []
    for line in chain(lines):
        simplified = outline.simplify(line, tolerance)
        if len(simplified) >= 2 and _planar_length(simplified) > tolerance * 2:
            paths.append(simplified)
    return paths


def chain(lines: list[list[tuple[float, float]]]) -> list[list[tuple[float, float]]]:
    """Join pieces that meet end to end into as few paths as possible, so each path
    generalises and encodes once; a real gap stays a gap."""

    def key(point: tuple[float, float]) -> tuple[int, int]:
        return (round(point[0] * 1e5), round(point[1] * 1e5))

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

    # Start from dead ends and junctions, so a path runs between them.
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


def route_entry(name: str, paths: list[list[tuple[float, float]]]) -> dict[str, Any]:
    """``{"name", "bbox": [s, w, n, e], "paths": [encoded polylines]}``, as the US
    writes its rail routes."""
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


def _planar_length(path: list[tuple[float, float]]) -> float:
    return sum(math.hypot(x2 - x1, y2 - y1) for (x1, y1), (x2, y2) in pairwise(path))
