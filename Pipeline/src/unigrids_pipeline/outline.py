"""Park outlines for the app's map: generalise, encode, and find where to put the pin.

The app draws every outline it ships, so each one is generalised for the scale it is
drawn at and written as encoded polylines (``UnigridsCore.Polyline`` decodes them). The
encoding is the common one at five decimal places, about a metre.
"""

from __future__ import annotations

import math
from collections.abc import Iterable, Sequence
from typing import Any

# A ring is a sequence of (longitude, latitude), as GeoJSON orders them.
Ring = list[tuple[float, float]]
Polygon = list[Ring]


def polygons_of(geometry: dict[str, Any] | None) -> list[Polygon]:
    """The polygons in a GeoJSON Polygon or MultiPolygon, as lists of rings."""
    if not geometry:
        return []
    kind = geometry.get("type")
    coordinates = geometry.get("coordinates") or []
    if kind == "Polygon":
        return [[_ring(ring) for ring in coordinates]]
    if kind == "MultiPolygon":
        return [[_ring(ring) for ring in polygon] for polygon in coordinates]
    return []


def _ring(points: Iterable[Sequence[float]]) -> Ring:
    ring = [(float(point[0]), float(point[1])) for point in points]
    if len(ring) > 1 and ring[0] == ring[-1]:
        ring.pop()
    return ring


def simplify(ring: Ring, tolerance: float) -> Ring:
    """Douglas–Peucker in degrees, with longitude scaled by the cosine of latitude so the
    tolerance means the same ground distance east–west as north–south."""
    if len(ring) <= 4 or tolerance <= 0:
        return list(ring)
    scale = math.cos(math.radians(sum(lat for _, lat in ring) / len(ring)))
    points = [(lon * scale, lat) for lon, lat in ring]
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    # An explicit stack: a long coastline recurses deeper than Python allows.
    stack = [(0, len(points) - 1)]
    while stack:
        start, end = stack.pop()
        furthest, index = 0.0, -1
        for i in range(start + 1, end):
            distance = _segment_distance(points[i], points[start], points[end])
            if distance > furthest:
                furthest, index = distance, i
        if index >= 0 and furthest > tolerance:
            keep[index] = True
            stack.append((start, index))
            stack.append((index, end))
    return [point for point, kept in zip(ring, keep, strict=True) if kept]


def _segment_distance(
    point: tuple[float, float], start: tuple[float, float], end: tuple[float, float]
) -> float:
    (px, py), (ax, ay), (bx, by) = point, start, end
    dx, dy = bx - ax, by - ay
    if dx == 0 and dy == 0:
        return math.hypot(px - ax, py - ay)
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def ring_area(ring: Ring) -> float:
    """Planar area in square degrees, unsigned. Only ever compared with another's."""
    total = 0.0
    for (x1, y1), (x2, y2) in zip(ring, ring[1:] + ring[:1], strict=True):
        total += x1 * y2 - x2 * y1
    return abs(total) / 2


def generalise(polygons: list[Polygon], tolerance: float) -> list[Polygon]:
    """Simplify every ring, and drop rings too small to see at the scale they are drawn.

    A ring is dropped when it collapses below a triangle, or when it is a speck — under a
    thousandth of the outline's largest polygon and smaller than the tolerance squared.
    Both conditions, so a park made of small islands keeps its islands.
    """
    largest = max((ring_area(polygon[0]) for polygon in polygons if polygon), default=0.0)
    speck = tolerance * tolerance * 4
    result: list[Polygon] = []
    for polygon in polygons:
        if not polygon:
            continue
        exterior = simplify(polygon[0], tolerance)
        area = ring_area(exterior)
        if len(exterior) < 3 or (area < largest / 1000 and area < speck):
            continue
        holes = [simplify(hole, tolerance) for hole in polygon[1:]]
        holes = [hole for hole in holes if len(hole) >= 3 and ring_area(hole) >= speck]
        result.append([exterior, *holes])
    return result


def encode(ring: Ring) -> str:
    """The encoded polyline of a ring, latitude first, at five decimal places."""
    output: list[str] = []
    previous_lat = previous_lon = 0
    for lon, lat in ring:
        lat_e5, lon_e5 = round(lat * 1e5), round(lon * 1e5)
        _append(lat_e5 - previous_lat, output)
        _append(lon_e5 - previous_lon, output)
        previous_lat, previous_lon = lat_e5, lon_e5
    return "".join(output)


def _append(value: int, output: list[str]) -> None:
    remaining = ~(value << 1) if value < 0 else value << 1
    while remaining >= 0x20:
        output.append(chr((0x20 | (remaining & 0x1F)) + 63))
        remaining >>= 5
    output.append(chr(remaining + 63))


def decode(encoded: str) -> Ring:
    """The inverse of :func:`encode`, for tests."""
    ring: Ring = []
    index = lat = lon = 0
    values: list[int] = []
    while index < len(encoded):
        result = shift = 0
        while True:
            chunk = ord(encoded[index]) - 63
            index += 1
            result |= (chunk & 0x1F) << shift
            shift += 5
            if chunk < 0x20:
                break
        values.append(~(result >> 1) if result & 1 else result >> 1)
        if len(values) == 2:
            lat += values[0]
            lon += values[1]
            ring.append((lon / 1e5, lat / 1e5))
            values = []
    return ring


def bbox(polygons: list[Polygon]) -> tuple[float, float, float, float] | None:
    """``(south, west, north, east)``."""
    points = [point for polygon in polygons for point in polygon[0]]
    if not points:
        return None
    lons = [lon for lon, _ in points]
    lats = [lat for _, lat in points]
    return (min(lats), min(lons), max(lats), max(lons))


def label_point(polygons: list[Polygon]) -> tuple[float, float] | None:
    """A point inside the largest polygon, as ``(latitude, longitude)``, for the pin.

    The centroid of a crescent or a horseshoe-shaped park falls outside it, so this takes
    the horizontal line through the centroid's latitude, finds where it crosses the
    polygon, and returns the middle of the widest stretch inside.
    """
    if not polygons:
        return None
    polygon = max(polygons, key=lambda p: ring_area(p[0]))
    exterior = polygon[0]
    centre_lat = (min(lat for _, lat in exterior) + max(lat for _, lat in exterior)) / 2
    crossings: list[float] = []
    for ring in polygon:
        for (x1, y1), (x2, y2) in zip(ring, ring[1:] + ring[:1], strict=True):
            if (y1 > centre_lat) != (y2 > centre_lat):
                crossings.append(x1 + (centre_lat - y1) * (x2 - x1) / (y2 - y1))
    crossings.sort()
    best: tuple[float, float] | None = None
    for left, right in zip(crossings[0::2], crossings[1::2], strict=False):
        if best is None or right - left > best[1] - best[0]:
            best = (left, right)
    if best is None:
        lon = sum(x for x, _ in exterior) / len(exterior)
        return (centre_lat, lon)
    return (centre_lat, (best[0] + best[1]) / 2)


def contains(polygons: list[Polygon], lon: float, lat: float) -> bool:
    """Even–odd point in polygon, matching ``BoundaryPolygon.contains`` in the app."""
    for polygon in polygons:
        inside = False
        for ring in polygon:
            for (x1, y1), (x2, y2) in zip(ring, ring[1:] + ring[:1], strict=True):
                if (y1 > lat) != (y2 > lat) and lon < x1 + (lat - y1) * (x2 - x1) / (y2 - y1):
                    inside = not inside
        if inside:
            return True
    return False
