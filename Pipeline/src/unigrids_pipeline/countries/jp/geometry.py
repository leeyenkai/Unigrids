"""Polygon work the Japanese sources need and the shared ``outline`` module does not do.

* **Union by shared edges.** The Ministry publishes each national park as its zones —
  special protection zone, special zones of three classes, ordinary zone, marine park
  zones — fifteen thousand polygons that tile each park exactly, vertex for vertex. A
  park's outline is their union. Where two zones meet, the edge they share appears once
  in each direction; cancelling those pairs leaves the park's boundary, which is then
  walked back into rings. No general-purpose clipping library is needed for data this
  clean, and the result keeps the source's own vertices.
* **Rings from OpenStreetMap ways**, for the quasi-national park outlines, which arrive
  as multipolygon relations: member ways joined end to end until they close.
* **Many points against one outline at once**, with numpy, for sampling which
  prefectures a park lies in, which huts stand inside it and which stations lie near it.
"""

from __future__ import annotations

import math
from collections import Counter
from collections.abc import Iterable, Sequence
from typing import Any

import numpy as np

from ... import outline

# Coordinates are compared as integers at this scale (1e-7 degrees, about a centimetre):
# the zones share their vertices exactly, and this only absorbs float noise.
_SCALE = 10_000_000

Key = tuple[int, int]


def _key(point: tuple[float, float]) -> Key:
    return (round(point[0] * _SCALE), round(point[1] * _SCALE))


def _signed_area_keys(ring: Sequence[Key]) -> float:
    total = 0.0
    for (x1, y1), (x2, y2) in zip(ring, [*ring[1:], ring[0]], strict=True):
        total += float(x1) * y2 - float(x2) * y1
    return total / 2


# MARK: - Union


def union(polygons: Iterable[outline.Polygon]) -> list[outline.Polygon]:
    """The union of polygons that meet along shared edges and do not overlap.

    Every ring is oriented with the interior on its left (exteriors counter-clockwise,
    holes clockwise), every directed edge counted, and each edge cancelled against its
    reverse. What survives is the boundary of the union, walked into rings by always
    taking the leftmost turn — so two parts that touch at a single vertex stay two rings.
    Rings come back as exteriors with their holes.
    """
    counts: Counter[tuple[Key, Key]] = Counter()
    for polygon in polygons:
        for index, ring in enumerate(polygon):
            keys = _dedupe([_key(point) for point in ring])
            if len(keys) < 3:
                continue
            area = _signed_area_keys(keys)
            if area == 0:
                continue
            if (area > 0) != (index == 0):
                keys.reverse()
            for start, end in zip(keys, [*keys[1:], keys[0]], strict=True):
                counts[(start, end)] += 1
    outgoing: dict[Key, list[Key]] = {}
    for (start, end), count in counts.items():
        # An edge left over once its reverse is cancelled is boundary. Two zones on the
        # same side of an edge would be an overlap; it is kept once, not twice.
        if count > counts.get((end, start), 0):
            outgoing.setdefault(start, []).append(end)
    rings = _walk(outgoing)
    return _assemble(rings)


def _dedupe(keys: list[Key]) -> list[Key]:
    result: list[Key] = []
    for key in keys:
        if not result or result[-1] != key:
            result.append(key)
    while len(result) > 1 and result[0] == result[-1]:
        result.pop()
    return result


def _walk(outgoing: dict[Key, list[Key]]) -> list[list[Key]]:
    """Rings from a set of directed boundary edges, leftmost turn first."""
    rings: list[list[Key]] = []
    for origin in list(outgoing):
        while outgoing.get(origin):
            first = outgoing[origin].pop()
            ring = [origin]
            previous, current = origin, first
            while current != origin or _has_left_continuation(
                outgoing, previous, current, first
            ):
                ring.append(current)
                candidates = outgoing.get(current)
                if not candidates:
                    break
                chosen = _leftmost(previous, current, candidates)
                candidates.remove(chosen)
                previous, current = current, chosen
            if len(ring) >= 3:
                rings.append(ring)
    return rings


def _has_left_continuation(
    outgoing: dict[Key, list[Key]], previous: Key, current: Key, first: Key
) -> bool:
    """Back at the ring's first vertex: whether the walk should carry on through it
    (another edge turns further left than the one the ring began with) rather than close."""
    candidates = outgoing.get(current)
    if not candidates:
        return False
    return _turn(previous, current, _leftmost(previous, current, candidates)) > _turn(
        previous, current, first
    )


def _turn(previous: Key, current: Key, following: Key) -> float:
    ax, ay = current[0] - previous[0], current[1] - previous[1]
    bx, by = following[0] - current[0], following[1] - current[1]
    return math.atan2(float(ax) * by - float(ay) * bx, float(ax) * bx + float(ay) * by)


def _leftmost(previous: Key, current: Key, candidates: list[Key]) -> Key:
    return max(candidates, key=lambda following: _turn(previous, current, following))


def _assemble(rings: list[list[Key]]) -> list[outline.Polygon]:
    """Rings as polygons: each hole (clockwise) given to the smallest exterior
    (counter-clockwise) that holds it. A hole nothing holds is dropped: it would be a
    hole in nothing."""
    exteriors: list[tuple[float, list[Key], tuple[int, int, int, int]]] = []
    holes: list[list[Key]] = []
    for ring in rings:
        area = _signed_area_keys(ring)
        if area > 0:
            xs = [x for x, _ in ring]
            ys = [y for _, y in ring]
            exteriors.append((area, ring, (min(xs), min(ys), max(xs), max(ys))))
        elif area < 0:
            holes.append(ring)
    exteriors.sort(key=lambda entry: entry[0])
    polygons: list[list[list[Key]]] = [[ring] for _, ring, _ in exteriors]
    for hole in holes:
        probes = hole[:: max(1, len(hole) // 5)][:5]
        for index, (_, ring, (west, south, east, north)) in enumerate(exteriors):
            inside = [
                west <= x <= east and south <= y <= north and _inside_keys(ring, x, y)
                for x, y in probes
            ]
            if sum(inside) * 2 > len(inside):
                polygons[index].append(hole)
                break
    return [
        [[(x / _SCALE, y / _SCALE) for x, y in ring] for ring in polygon]
        for polygon in polygons
    ]


def _inside_keys(ring: list[Key], x: int, y: int) -> bool:
    inside = False
    for (x1, y1), (x2, y2) in zip(ring, [*ring[1:], ring[0]], strict=True):
        if (y1 > y) != (y2 > y) and x < x1 + (y - y1) * (x2 - x1) / (y2 - y1):
            inside = not inside
    return inside


# MARK: - OpenStreetMap multipolygons


def osm_polygons(element: dict[str, Any]) -> list[outline.Polygon]:
    """The polygons of an Overpass ``out geom`` way or multipolygon relation.

    A closed way is one ring. A relation's outer and inner member ways are joined end to
    end into rings — mappers split a long boundary into many ways — and each inner ring
    goes to the outer ring that holds it. Ways that never close are left out.
    """
    if element.get("type") == "way":
        ring = _points(element.get("geometry"))
        return [[ring]] if len(ring) >= 3 and ring[0] == ring[-1] else []
    outers, inners = [], []
    for member in element.get("members") or []:
        if member.get("type") != "way":
            continue
        points = _points(member.get("geometry"))
        if len(points) >= 2:
            (inners if member.get("role") == "inner" else outers).append(points)
    outer_rings = [ring for ring in _join(outers) if len(ring) >= 4]
    inner_rings = [ring for ring in _join(inners) if len(ring) >= 4]
    polygons: list[outline.Polygon] = [[_open(ring)] for ring in outer_rings]
    for ring in inner_rings:
        hole = _open(ring)
        lon, lat = hole[0]
        for polygon in polygons:
            if outline.contains([[polygon[0]]], lon, lat):
                polygon.append(hole)
                break
    return polygons


def _open(ring: list[tuple[float, float]]) -> outline.Ring:
    """A closed ring without its repeated closing point, as ``outline`` keeps rings."""
    return ring[:-1] if len(ring) > 1 and ring[0] == ring[-1] else list(ring)


def _points(geometry: list[dict[str, float]] | None) -> list[tuple[float, float]]:
    return [
        (float(node["lon"]), float(node["lat"]))
        for node in geometry or []
        if node and "lon" in node and "lat" in node
    ]


def _join(pieces: list[list[tuple[float, float]]]) -> list[list[tuple[float, float]]]:
    """Ways joined at shared end nodes into closed rings, reversing any that run the
    wrong way. A chain that cannot be closed is dropped."""
    remaining = [list(piece) for piece in pieces]
    rings: list[list[tuple[float, float]]] = []
    while remaining:
        ring = remaining.pop()
        progressed = True
        while _key(ring[0]) != _key(ring[-1]) and progressed:
            progressed = False
            end = _key(ring[-1])
            for index, piece in enumerate(remaining):
                if _key(piece[0]) == end:
                    ring.extend(piece[1:])
                elif _key(piece[-1]) == end:
                    ring.extend(reversed(piece[:-1]))
                else:
                    continue
                remaining.pop(index)
                progressed = True
                break
        if len(ring) >= 4 and _key(ring[0]) == _key(ring[-1]):
            rings.append(ring)
    return rings


# MARK: - Many points at once


def _edges(polygons: list[outline.Polygon]) -> np.ndarray:
    """Every ring edge of a multipolygon as rows ``x1, y1, x2, y2``."""
    rows = []
    for polygon in polygons:
        for ring in polygon:
            if len(ring) < 3:
                continue
            points = np.asarray(ring, dtype=float)
            rows.append(np.hstack([points, np.roll(points, -1, axis=0)]))
    return np.vstack(rows) if rows else np.zeros((0, 4))


def contains_many(
    polygons: list[outline.Polygon], points: Sequence[tuple[float, float]]
) -> np.ndarray:
    """Whether each ``(lon, lat)`` lies inside the multipolygon, even–odd over every ring.

    The same rule as ``outline.contains`` for polygons that do not overlap one another,
    which a union and an OSM multipolygon do not.
    """
    if not points:
        return np.zeros(0, dtype=bool)
    edges = _edges(polygons)
    xs = np.asarray([point[0] for point in points], dtype=float)
    ys = np.asarray([point[1] for point in points], dtype=float)
    parity = np.zeros(len(xs), dtype=bool)
    # In slices, so a long coastline against a few thousand points stays in memory.
    step = max(1, 4_000_000 // max(1, len(xs)))
    for start in range(0, len(edges), step):
        x1, y1, x2, y2 = (edges[start : start + step, i][:, None] for i in range(4))
        crosses = (y1 > ys) != (y2 > ys)
        with np.errstate(divide="ignore", invalid="ignore"):
            at = x1 + (ys - y1) * (x2 - x1) / (y2 - y1)
        hits = crosses & (xs < at)
        parity ^= (hits.sum(axis=0) % 2).astype(bool)
    return parity


def near_many(
    polygons: list[outline.Polygon], points: Sequence[tuple[float, float]], metres: float
) -> np.ndarray:
    """Whether each ``(lon, lat)`` lies inside the multipolygon or within ``metres`` of one
    of its vertices — a hole's as well, since a town a park surrounds is near it. Meant
    for a distance far larger than the gaps between vertices, where the nearest vertex
    stands for the nearest edge."""
    if not points:
        return np.zeros(0, dtype=bool)
    vertices = np.asarray(
        [vertex for polygon in polygons for ring in polygon for vertex in ring], dtype=float
    )
    xs = np.asarray([point[0] for point in points], dtype=float)
    ys = np.asarray([point[1] for point in points], dtype=float)
    near = np.zeros(len(xs), dtype=bool)
    if len(vertices):
        step = max(1, 4_000_000 // max(1, len(xs)))
        for start in range(0, len(vertices), step):
            chunk = vertices[start : start + step]
            lat = np.radians((chunk[:, 1][:, None] + ys) / 2)
            dx = np.radians(chunk[:, 0][:, None] - xs) * np.cos(lat)
            dy = np.radians(chunk[:, 1][:, None] - ys)
            metres_away = np.hypot(dx, dy) * 6_371_008.8
            near |= (metres_away <= metres).any(axis=0)
    return near | contains_many(polygons, points)


# MARK: - Prefectures


class Prefectures:
    """Which prefectures a place lies in, by sampling points against their outlines —
    the rule ``lands_build`` applies to US states."""

    def __init__(self, features: list[tuple[str, list[outline.Polygon]]]) -> None:
        self._features = [
            (code, polygons, box)
            for code, polygons in features
            if polygons and (box := outline.bbox(polygons)) is not None
        ]

    @property
    def codes(self) -> list[str]:
        return [code for code, _, _ in self._features]

    def at_many(self, points: Sequence[tuple[float, float]]) -> list[str | None]:
        """The prefecture each ``(lon, lat)`` falls in, or ``None`` (at sea)."""
        found: list[str | None] = [None] * len(points)
        for code, polygons, (south, west, north, east) in self._features:
            candidates = [
                index
                for index, (lon, lat) in enumerate(points)
                if found[index] is None and south <= lat <= north and west <= lon <= east
            ]
            if not candidates:
                continue
            inside = contains_many(polygons, [points[index] for index in candidates])
            for index, hit in zip(candidates, inside, strict=True):
                if hit:
                    found[index] = code
        return found

    def of_polygons(
        self,
        polygons: list[outline.Polygon],
        share: float,
        *,
        steps: int = 64,
    ) -> list[str]:
        """Every prefecture holding at least ``share`` of the place, largest first.

        A grid of points over the place, kept where they fall inside it; shares are of
        the points that land in some prefecture, because a coastal park's sea is in none.
        A place too small or too scattered for the grid samples its outline's vertices.
        """
        box = outline.bbox(polygons)
        if box is None:
            return []
        south, west, north, east = box
        grid = [
            (west + (east - west) * (column + 0.5) / steps,
             south + (north - south) * (row + 0.5) / steps)
            for row in range(steps)
            for column in range(steps)
        ]
        inside = contains_many(polygons, grid)
        samples = [point for point, hit in zip(grid, inside, strict=True) if hit]
        if len(samples) < 40:
            vertices = [point for polygon in polygons for point in polygon[0]]
            samples += vertices[:: max(1, len(vertices) // 400)]
        return self.of_points(samples, share)

    def nearest(self, point: tuple[float, float]) -> list[str]:
        """The prefecture a ``(lon, lat)`` lies in, or else the one with the outline
        vertex nearest to it — for a place out at sea — as a one-item list."""
        if code := self.at_many([point])[0]:
            return [code]
        lon, lat = point
        scale = math.cos(math.radians(lat))
        best: tuple[float, str] | None = None
        for code, polygons, _ in self._features:
            vertices = np.asarray([v for polygon in polygons for v in polygon[0]], dtype=float)
            distance = float(
                (((vertices[:, 0] - lon) * scale) ** 2 + (vertices[:, 1] - lat) ** 2).min()
            )
            if best is None or distance < best[0]:
                best = (distance, code)
        return [best[1]] if best else []

    def of_points(self, samples: Sequence[tuple[float, float]], share: float) -> list[str]:
        counts = Counter(code for code in self.at_many(samples) if code)
        located = sum(counts.values())
        if not located:
            return []
        ordered = sorted(counts, key=lambda code: (-counts[code], code))
        kept = [code for code in ordered if counts[code] / located >= share]
        return kept or ordered[:1]
