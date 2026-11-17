"""OpenStreetMap read from a Geofabrik extract instead of asked of Overpass.

Overpass is volunteer-run and turns a long fetch away partway, which left most of Japan's
parks without huts or trails. Geofabrik publishes the whole country as one ``.osm.pbf``,
refreshed daily; this module downloads it once (resumably — it is 2.5 GB) and reads out of
it exactly the elements the Overpass queries would have returned, **in Overpass JSON's own
shapes**, so the files written from it are the files the build already reads and every key
built from an OSM id stays the key it was.

The selection mirrors Overpass's semantics where they matter here:

* an element "in" a box is one with a node in it or a segment crossing it, and comes back
  whole, never clipped;
* ``out geom`` gives a way its ``bounds``, ``nodes`` and ``geometry``, and a relation its
  ``bounds`` and each way member its ``geometry`` (node members their ``lat``/``lon``);
* ``out center`` gives a way or relation a ``center``, the middle of its bounds.

Three streaming passes over the file — relations, then ways, then nodes — each with the
ids the previous pass found wanting. No node-location index of the whole country is
built: only the nodes the selected ways use are kept, which is a few million, not the
extract's hundreds of millions.
"""

from __future__ import annotations

import contextlib
import hashlib
import itertools
import json
import math
import re
import time
from collections.abc import Iterable, Iterator
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import httpx

from ..rawstore import FetchRecord, SourceTerms
from . import http

GEOFABRIK_JAPAN = "https://download.geofabrik.de/asia/japan-latest.osm.pbf"
SOURCE = "geofabrik"
JAPAN_FILE = "japan-latest.osm.pbf"

GEOFABRIK_TERMS = SourceTerms(
    identifier="geofabrik-osm-extract",
    title="OpenStreetMap extract from Geofabrik (download.geofabrik.de)",
    url="https://www.openstreetmap.org/copyright",
    licence="Open Database License (ODbL) 1.0",
    attribution="© OpenStreetMap contributors",
    notes=(
        "The whole-country extract, read locally for huts, stations, rail and trails in place "
        "of Overpass queries. Geofabrik redistributes OSM data under the ODbL unchanged."
    ),
)

Record = dict[str, Any]
Box = tuple[float, float, float, float]
"""South, west, north, east — Overpass's order."""


# MARK: - Download


def download(
    directory: Path,
    *,
    url: str = GEOFABRIK_JAPAN,
    filename: str = JAPAN_FILE,
    refresh: bool = False,
    chunk_bytes: int = 1 << 22,
) -> Path:
    """The extract at ``directory/filename``, downloaded if it is not there yet.

    ``-latest`` redirects to a dated file; the dated URL is what is fetched, so a download
    resumed with a ``Range`` request keeps reading the same bytes even if Geofabrik
    publishes the next day's file meanwhile. A ``.part`` file survives an interruption and
    the next call carries on from its end.
    """
    path = directory / filename
    if path.exists() and not refresh:
        return path
    directory.mkdir(parents=True, exist_ok=True)
    partial = path.with_name(path.name + ".part")
    resolved = partial.with_name(path.name + ".url")
    with http.client(http.Politeness(timeout_seconds=600.0)) as session:
        if refresh or not resolved.exists() or not partial.exists():
            dated = _resolve(session, url)
            if resolved.exists() and resolved.read_text().strip() != dated:
                partial.unlink(missing_ok=True)
            resolved.write_text(dated + "\n")
        dated = resolved.read_text().strip()
        headers: dict[str, str] = {}
        for attempt in range(8):
            if attempt:
                time.sleep(min(120, 5 * 2**attempt))
            start = partial.stat().st_size if partial.exists() else 0
            request = {"Range": f"bytes={start}-"} if start else {}
            try:
                with session.stream("GET", dated, headers=request) as response:
                    if response.status_code == 416:  # nothing left to send
                        break
                    if response.status_code in http.RETRY_STATUS:
                        continue
                    response.raise_for_status()
                    if start and response.status_code != 206:
                        start = 0  # the server ignored the range; start over
                    headers = {
                        key: response.headers[key]
                        for key in ("last-modified", "etag", "content-length", "content-range")
                        if key in response.headers
                    }
                    with partial.open("ab" if start else "wb") as handle:
                        for chunk in response.iter_bytes(chunk_bytes):
                            handle.write(chunk)
                total = _total_size(headers)
                if total is None or partial.stat().st_size >= total:
                    break
            except httpx.HTTPError as error:
                print(f"    {SOURCE}: {error}; resuming", flush=True)
        else:
            raise http.FetchError(f"{dated} did not finish downloading after 8 attempts")
    partial.replace(path)
    record = FetchRecord(source=GEOFABRIK_TERMS, fetched_at=_utc_now())
    record.add_request(url, resolved=dated, headers=headers)
    record.files.append({
        "path": path.relative_to(directory).as_posix(),
        "bytes": path.stat().st_size,
        "sha256": sha256(path),
        **({"replicationTimestamp": stamp} if (stamp := replication_timestamp(path)) else {}),
    })
    record.write(directory)
    resolved.unlink(missing_ok=True)
    return path


def latest(source: str = SOURCE, filename: str = JAPAN_FILE) -> Path | None:
    """The newest extract already downloaded, if any."""
    from .. import rawstore

    directory = rawstore.latest(source, filename)
    return directory / filename if directory else None


def describe(extract: Path) -> dict[str, Any]:
    """Where an extract came from, for the ``source.json`` of every file read out of it:
    its dated URL, its place in the raw store, its SHA-256 and the moment its data stands
    at — enough to say exactly which OpenStreetMap a raw file was cut from."""
    described: dict[str, Any] = {"url": GEOFABRIK_JAPAN, "extract": extract.name}
    record = extract.parent / "source.json"
    if record.exists():
        payload = json.loads(record.read_text())
        for request in payload.get("requests") or []:
            described["url"] = request.get("resolved") or request.get("url") or described["url"]
        for entry in payload.get("files") or []:
            if entry.get("path") == extract.name:
                described["sha256"] = entry.get("sha256")
                if stamp := entry.get("replicationTimestamp"):
                    described["replicationTimestamp"] = stamp
    with contextlib.suppress(IndexError, ValueError):
        described["extract"] = extract.relative_to(extract.parents[2]).as_posix()
    return described


def _resolve(session: httpx.Client, url: str) -> str:
    """Where ``-latest`` points today."""
    response = session.head(url, follow_redirects=False)
    location = response.headers.get("location")
    if response.status_code in (301, 302, 303, 307, 308) and location:
        return str(httpx.URL(url).join(location))
    return url


def _total_size(headers: dict[str, str]) -> int | None:
    if (ranged := headers.get("content-range")) and (match := re.search(r"/(\d+)$", ranged)):
        return int(match.group(1))
    if length := headers.get("content-length"):
        return int(length)
    return None


def _utc_now() -> str:
    from ..rawstore import utc_now

    return utc_now()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(1 << 24):
            digest.update(chunk)
    return digest.hexdigest()


def replication_timestamp(path: Path) -> str | None:
    """The moment the extract's data stands at, from the PBF header."""
    import osmium

    header = osmium.io.Reader(str(path), osmium.osm.osm_entity_bits.NOTHING).header()
    stamp = header.get("osmosis_replication_timestamp", "")
    return stamp or None


# MARK: - Selection


@dataclass(frozen=True)
class TagRule:
    """One Overpass tag filter list: every ``(key, pattern)`` must hold. A pattern of
    ``None`` asks only that the key exist; otherwise it is a regular expression matched
    with ``re.search``, as Overpass's ``~`` is."""

    rules: tuple[tuple[str, str | None], ...]

    def matches(self, tags: dict[str, str]) -> bool:
        for key, pattern in self.rules:
            value = tags.get(key)
            if value is None:
                return False
            if pattern is not None and not re.search(pattern, value):
                return False
        return True


def tag_rule(**rules: str | None) -> TagRule:
    return TagRule(tuple(rules.items()))


HUT_RULE = tag_rule(tourism="^(alpine_hut|wilderness_hut)$")
STATION_RULE = tag_rule(railway="^(station|halt)$")
TRAIN_ROUTE_RULE = tag_rule(route="^train$")
HIKING_RULE = tag_rule(route="^hiking$")


def rounded(box: Box, places: int) -> Box:
    """A box as an Overpass query prints it (``{south:.5f},…``): the query's edges, not the
    unrounded ones, decide what lies on the boundary."""
    south, west, north, east = (float(f"{value:.{places}f}") for value in box)
    return (south, west, north, east)


def trail_way_rule(kinds: str) -> TagRule:
    return TagRule((("highway", f"^({kinds})$"), ("name", None)))


@dataclass
class Request:
    """What one raw file holds: the selections, each over its own box.

    ``huts`` — ``nwr[tourism~huts](box); out center tags;``
    ``stations`` — ``node[railway~station|halt](box); out;``
    ``rail`` — ``RAIL_QUERY``: train routes touching the box, their route masters, member
    ways with a railway tag (``out geom``) and member nodes (``out``), plus the stations
    those routes stop at (see ``main_stations``).
    ``trails`` — ``OSM_QUERY``: hiking relations and named ``highway~kinds`` ways touching
    the box, ``out geom``.
    """

    name: str
    huts: Box | None = None
    stations: Box | None = None
    rail: Box | None = None
    trails: Box | None = None
    trail_kinds: str = "path|footway"
    stations_near_stops: bool = True


STOP_AREA_REACH_M = 300.0
"""How far a station node may sit from a stop a route uses and still be that stop's
station, when no ``stop_area`` relation says so."""


@dataclass
class _Store:
    relations: dict[int, Record] = field(default_factory=dict)
    ways: dict[int, Record] = field(default_factory=dict)
    nodes: dict[int, Record] = field(default_factory=dict)
    locations: dict[int, tuple[float, float]] = field(default_factory=dict)


def select(path: Path, requests: list[Request]) -> dict[str, list[Record]]:
    """Every request's elements, read from the extract at ``path``.

    Returns, per request name, the elements in the order Overpass prints them for that
    request's query. Each scan of the file is narrowed by a filter that runs inside
    libosmium, so Python only ever sees the few hundred thousand objects that matter.
    """
    import osmium
    from osmium.filter import IdFilter, TagFilter

    wants_rail = any(request.rail for request in requests)
    wants_trails = any(request.trails for request in requests)
    wants_huts = any(request.huts for request in requests)
    wants_stations = wants_rail or any(request.stations for request in requests)
    way_rules = [trail_way_rule(kind) for kind in {r.trail_kinds for r in requests if r.trails}]
    store = _Store()
    source = str(path)

    def scan(kind: Any, *tags: tuple[str, str], ids: Iterable[int] | None = None) -> Any:
        processor = osmium.FileProcessor(source, kind)
        if ids is not None:
            processor = processor.with_filter(IdFilter(ids))
        if tags:
            processor = processor.with_filter(TagFilter(*tags))
        return processor

    # Relations: train routes, their masters and stop areas; hiking routes; huts.
    relation_tags = [
        *([("route", "train"), ("type", "route_master"), ("public_transport", "stop_area")]
          if wants_rail else []),
        *([("route", "hiking")] if wants_trails else []),
        *(_HUT_TAGS if wants_huts else []),
    ]
    want_way_ids: set[int] = set()
    want_node_ids: set[int] = set()
    if relation_tags:
        for relation in scan(osmium.osm.RELATION, *relation_tags):
            tags = dict(relation.tags)
            members = [
                {"type": _MEMBER_TYPE[member.type], "ref": member.ref, "role": member.role}
                for member in relation.members
            ]
            store.relations[relation.id] = {
                "type": "relation", "id": relation.id, "members": members, "tags": tags,
            }
            # A master lists routes, a stop area its own stops: neither needs geometry.
            if tags.get("type") == "route_master" or tags.get("public_transport") == "stop_area":
                continue
            for member in members:
                if member["type"] == "way":
                    want_way_ids.add(member["ref"])
                elif member["type"] == "node":
                    want_node_ids.add(member["ref"])

    # Ways: the members just found, then named trail ways and hut ways by tag.
    def keep_way(way: Any) -> None:
        refs = [node.ref for node in way.nodes]
        store.ways[way.id] = {"type": "way", "id": way.id, "nodes": refs, "tags": dict(way.tags)}
        want_node_ids.update(refs)

    if want_way_ids:
        for way in scan(osmium.osm.WAY, ids=want_way_ids):
            keep_way(way)
    way_tags = [
        *({("highway", kind) for rule in way_rules for kind in _alternatives(rule)}),
        *(_HUT_TAGS if wants_huts else []),
    ]
    if way_tags:
        for way in scan(osmium.osm.WAY, *sorted(way_tags)):
            if way.id in store.ways:
                continue
            tags = dict(way.tags)
            if any(rule.matches(tags) for rule in way_rules) or (
                wants_huts and HUT_RULE.matches(tags)
            ):
                keep_way(way)

    # Nodes: every one a kept way or relation uses, then huts and stations by tag.
    def keep_node(node: Any, tags: dict[str, str]) -> None:
        location = (round(node.location.lat, 7), round(node.location.lon, 7))
        store.locations[node.id] = location
        if tags:
            store.nodes[node.id] = _node(node.id, location, tags)

    if want_node_ids:
        for node in scan(osmium.osm.NODE, ids=want_node_ids):
            if node.location.valid():
                keep_node(node, dict(node.tags))
    node_tags = [
        *(_HUT_TAGS if wants_huts else []),
        *(_STATION_TAGS if wants_stations else []),
    ]
    if node_tags:
        for node in scan(osmium.osm.NODE, *node_tags):
            if node.id in store.nodes or not node.location.valid():
                continue
            tags = dict(node.tags)
            if HUT_RULE.matches(tags) or _is_station(tags):
                keep_node(node, tags)

    return {request.name: _assemble(store, request) for request in requests}


_HUT_TAGS = [("tourism", "alpine_hut"), ("tourism", "wilderness_hut")]
_STATION_TAGS = [("railway", "station"), ("railway", "halt"), ("public_transport", "station")]


def _alternatives(rule: TagRule) -> list[str]:
    """The values an anchored alternation ``^(a|b)$`` allows, for a libosmium tag filter."""
    pattern = dict(rule.rules)["highway"] or ""
    match = re.fullmatch(r"\^\(([^()]*)\)\$", pattern)
    if not match:
        raise ValueError(f"{pattern!r} is not an anchored list of values")
    return match.group(1).split("|")


_MEMBER_TYPE = {"n": "node", "w": "way", "r": "relation"}


def _is_station(tags: dict[str, str]) -> bool:
    return tags.get("railway") in ("station", "halt") or (
        tags.get("public_transport") == "station" and tags.get("train") == "yes"
    )


def _node(node_id: int, location: tuple[float, float], tags: dict[str, str]) -> Record:
    element: Record = {"type": "node", "id": node_id, "lat": location[0], "lon": location[1]}
    if tags:
        element["tags"] = tags
    return element


# MARK: - Assembly per request


def _assemble(store: _Store, request: Request) -> list[Record]:
    elements: list[Record] = []
    if request.huts:
        elements.extend(_huts(store, request.huts))
    if request.stations:
        elements.extend(
            store.nodes[node_id] | {}
            for node_id in sorted(store.nodes)
            if STATION_RULE.matches(store.nodes[node_id].get("tags", {}))
            and _point_in(store.locations[node_id], request.stations)
        )
    if request.rail:
        elements.extend(_rail(store, request.rail, near_stops=request.stations_near_stops))
    if request.trails:
        elements.extend(_trails(store, request.trails, request.trail_kinds))
    return elements


def _huts(store: _Store, box: Box) -> Iterator[Record]:
    for node_id in sorted(store.nodes):
        node = store.nodes[node_id]
        if HUT_RULE.matches(node.get("tags", {})) and _point_in(store.locations[node_id], box):
            yield {"type": "node", "id": node_id, "lat": node["lat"], "lon": node["lon"],
                   "tags": node["tags"]}
    for way_id in sorted(store.ways):
        way = store.ways[way_id]
        if not HUT_RULE.matches(way["tags"]):
            continue
        points = _way_points(store, way)
        if points and _line_touches(points, box):
            yield {"type": "way", "id": way_id, "center": _center(points), "tags": way["tags"]}
    for relation_id in sorted(store.relations):
        relation = store.relations[relation_id]
        if not HUT_RULE.matches(relation["tags"]):
            continue
        points = _relation_points(store, relation)
        if points and _relation_touches(store, relation, box):
            yield {"type": "relation", "id": relation_id, "center": _center(points),
                   "tags": relation["tags"]}


def _rail(store: _Store, box: Box, *, near_stops: bool) -> list[Record]:
    routes = [
        store.relations[relation_id]
        for relation_id in sorted(store.relations)
        if TRAIN_ROUTE_RULE.matches(store.relations[relation_id]["tags"])
        and _relation_touches(store, store.relations[relation_id], box)
    ]
    route_ids = {route["id"] for route in routes}
    masters = [
        store.relations[relation_id]
        for relation_id in sorted(store.relations)
        if store.relations[relation_id]["tags"].get("type") == "route_master"
        and any(
            member["type"] == "relation" and member["ref"] in route_ids
            for member in store.relations[relation_id]["members"]
        )
    ]
    way_ids: set[int] = set()
    node_ids: set[int] = set()
    for route in routes:
        for member in route["members"]:
            if member["type"] == "way":
                way_ids.add(member["ref"])
            elif member["type"] == "node":
                node_ids.add(member["ref"])
    ways = [
        _way_geom(store, store.ways[way_id])
        for way_id in sorted(way_ids)
        if way_id in store.ways and "railway" in store.ways[way_id]["tags"]
    ]
    ways = [way for way in ways if way]
    nodes = [_member_node(store, node_id) for node_id in sorted(node_ids)]
    nodes = [node for node in nodes if node]
    if near_stops:
        extra = sorted(main_stations(store, node_ids) - node_ids)
        nodes.extend(store.nodes[node_id] for node_id in extra)
    return [*(_body(route) for route in routes), *(_body(master) for master in masters),
            *ways, *nodes]


def main_stations(store: _Store, stop_ids: set[int]) -> set[int]:
    """Station nodes that serve the stops ``stop_ids``: members of a ``stop_area`` with
    one of those stops, or within ``STOP_AREA_REACH_M`` of one.

    A big station's route members are its platforms' stop positions; the ``railway=station``
    node that names Tokyo or Shin-Osaka is not a member of any route, only of the stop
    area. Without it a line's stations would leave out the very stations people travel to.
    """
    found: set[int] = set()
    for relation in store.relations.values():
        if relation["tags"].get("public_transport") != "stop_area":
            continue
        members = {member["ref"] for member in relation["members"] if member["type"] == "node"}
        if members & stop_ids:
            found.update(
                node_id for node_id in members
                if node_id in store.nodes and _is_station(store.nodes[node_id].get("tags", {}))
            )
    stations = [
        node_id for node_id, node in store.nodes.items()
        if _is_station(node.get("tags", {}))
    ]
    if stations:
        grid = _Grid(STOP_AREA_REACH_M)
        for node_id in stations:
            grid.add(node_id, store.locations[node_id])
        for stop_id in stop_ids:
            if (location := store.locations.get(stop_id)) is None:
                continue
            found.update(grid.near(location))
    return found


class _Grid:
    """A coarse lat/lon grid for "within so many metres" over many points."""

    def __init__(self, reach_m: float) -> None:
        self.reach_m = reach_m
        self.cell = reach_m / 111_000.0 * 2
        self.cells: dict[tuple[int, int], list[tuple[int, tuple[float, float]]]] = {}

    def _key(self, location: tuple[float, float]) -> tuple[int, int]:
        return (math.floor(location[0] / self.cell), math.floor(location[1] / self.cell))

    def add(self, item: int, location: tuple[float, float]) -> None:
        self.cells.setdefault(self._key(location), []).append((item, location))

    def near(self, location: tuple[float, float]) -> Iterator[int]:
        row, column = self._key(location)
        for d_row in (-1, 0, 1):
            for d_column in (-1, 0, 1):
                for item, other in self.cells.get((row + d_row, column + d_column), ()):
                    if _metres(location, other) <= self.reach_m:
                        yield item


def _metres(a: tuple[float, float], b: tuple[float, float]) -> float:
    lat = math.radians((a[0] + b[0]) / 2)
    dy = (a[0] - b[0]) * 111_195.0
    dx = (a[1] - b[1]) * 111_195.0 * math.cos(lat)
    return math.hypot(dx, dy)


def _trails(store: _Store, box: Box, kinds: str) -> list[Record]:
    rule = trail_way_rule(kinds)
    ways = []
    for way_id in sorted(store.ways):
        way = store.ways[way_id]
        if not rule.matches(way["tags"]):
            continue
        points = _way_points(store, way)
        if points and _line_touches(points, box):
            geometry = _way_geom(store, way)
            if geometry:
                ways.append(geometry)
    relations = []
    for relation_id in sorted(store.relations):
        relation = store.relations[relation_id]
        if HIKING_RULE.matches(relation["tags"]) and _relation_touches(store, relation, box):
            relations.append(_relation_geom(store, relation))
    return [*ways, *relations]


# MARK: - Overpass shapes


def _body(relation: Record) -> Record:
    return {"type": "relation", "id": relation["id"],
            "members": [dict(member) for member in relation["members"]],
            "tags": relation["tags"]}


def _member_node(store: _Store, node_id: int) -> Record | None:
    if node_id in store.nodes:
        return store.nodes[node_id]
    if (location := store.locations.get(node_id)) is None:
        return None
    return _node(node_id, location, {})


def _way_points(store: _Store, way: Record) -> list[tuple[float, float]]:
    return [store.locations[ref] for ref in way["nodes"] if ref in store.locations]


def _way_geom(store: _Store, way: Record) -> Record | None:
    points = _way_points(store, way)
    if not points:
        return None
    element: Record = {"type": "way", "id": way["id"], "bounds": _bounds(points),
                       "nodes": list(way["nodes"]), "geometry": _latlons(points)}
    if way["tags"]:
        element["tags"] = way["tags"]
    return element


def _relation_points(store: _Store, relation: Record) -> list[tuple[float, float]]:
    points: list[tuple[float, float]] = []
    for member in relation["members"]:
        if member["type"] == "node" and (location := store.locations.get(member["ref"])):
            points.append(location)
        elif member["type"] == "way" and (way := store.ways.get(member["ref"])):
            points.extend(_way_points(store, way))
    return points


def _relation_geom(store: _Store, relation: Record) -> Record:
    members = []
    for member in relation["members"]:
        entry = dict(member)
        if member["type"] == "way" and (way := store.ways.get(member["ref"])):
            entry["geometry"] = _latlons(_way_points(store, way))
        elif member["type"] == "node" and (location := store.locations.get(member["ref"])):
            entry["lat"], entry["lon"] = location
        members.append(entry)
    element: Record = {"type": "relation", "id": relation["id"]}
    if points := _relation_points(store, relation):
        element["bounds"] = _bounds(points)
    element["members"] = members
    element["tags"] = relation["tags"]
    return element


def _latlons(points: list[tuple[float, float]]) -> list[Record]:
    return [{"lat": lat, "lon": lon} for lat, lon in points]


def _bounds(points: list[tuple[float, float]]) -> Record:
    lats = [lat for lat, _ in points]
    lons = [lon for _, lon in points]
    return {"minlat": min(lats), "minlon": min(lons), "maxlat": max(lats), "maxlon": max(lons)}


def _center(points: list[tuple[float, float]]) -> Record:
    bounds = _bounds(points)
    return {
        "lat": round((bounds["minlat"] + bounds["maxlat"]) / 2, 7),
        "lon": round((bounds["minlon"] + bounds["maxlon"]) / 2, 7),
    }


# MARK: - Geometry


def _point_in(point: tuple[float, float], box: Box) -> bool:
    south, west, north, east = box
    return south <= point[0] <= north and west <= point[1] <= east


def _line_touches(points: list[tuple[float, float]], box: Box) -> bool:
    """Whether a polyline has a vertex in the box or a segment crossing it."""
    if any(_point_in(point, box) for point in points):
        return True
    return any(_segment_crosses(a, b, box) for a, b in itertools.pairwise(points))


def _segment_crosses(a: tuple[float, float], b: tuple[float, float], box: Box) -> bool:
    """Liang–Barsky: whether segment ``ab`` passes through the box."""
    south, west, north, east = box
    x0, y0, x1, y1 = a[1], a[0], b[1], b[0]
    dx, dy = x1 - x0, y1 - y0
    low, high = 0.0, 1.0
    for p, q in ((-dx, x0 - west), (dx, east - x0), (-dy, y0 - south), (dy, north - y0)):
        if p == 0:
            if q < 0:
                return False
            continue
        t = q / p
        if p < 0:
            low = max(low, t)
        else:
            high = min(high, t)
        if low > high:
            return False
    return True


def _relation_touches(store: _Store, relation: Record, box: Box) -> bool:
    """Overpass's ``rel(bbox)``: a member node in the box or a member way touching it."""
    for member in relation["members"]:
        if member["type"] == "node":
            if (location := store.locations.get(member["ref"])) and _point_in(location, box):
                return True
        elif member["type"] == "way" and (way := store.ways.get(member["ref"])):
            points = _way_points(store, way)
            if points and _line_touches(points, box):
                return True
    return False


def write_elements(path: Path, elements: list[Record], **header: Any) -> Path:
    """An Overpass-shaped answer file."""
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {**header, "elements": elements}
    path.write_text(json.dumps(payload, ensure_ascii=False))
    return path
