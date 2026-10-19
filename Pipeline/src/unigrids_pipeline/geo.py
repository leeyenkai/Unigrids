"""Coordinate, distance and tile maths.

Two coordinate systems and nothing else:

* **WGS84 longitude/latitude**, which is what every source publishes and what the app
  stores.
* **Web Mercator (EPSG:3857) metres**, which is what the tile grid and the elevation
  raster live in, because that is the projection ``MKTileOverlay`` expects.

Distances are measured on the WGS84 ellipsoid, never in Mercator metres: Mercator
stretches by ``1 / cos(latitude)``, so a trail measured there would come out 25 % long at
Zion's latitude and 100 % long in Alaska.
"""

from __future__ import annotations

import math
from collections.abc import Iterable, Sequence
from dataclasses import dataclass

# WGS84.
EARTH_SEMI_MAJOR_M = 6378137.0
EARTH_FLATTENING = 1.0 / 298.257223563
ECCENTRICITY_SQUARED = EARTH_FLATTENING * (2.0 - EARTH_FLATTENING)

# The sphere with the same surface area as the WGS84 ellipsoid. Used for polygon areas,
# where it keeps the error under about 0.1 % — fine for a park's size in km², and the
# alternative is an elliptic integral per ring.
EARTH_AUTHALIC_RADIUS_M = 6371007.181

# Web Mercator's own radius, and the half-circumference every tile calculation is
# relative to.
MERCATOR_RADIUS_M = 6378137.0
MERCATOR_ORIGIN_SHIFT_M = math.pi * MERCATOR_RADIUS_M

# Web Mercator cannot represent the poles.
MERCATOR_MAX_LATITUDE = 85.051128779806604

Coordinate = tuple[float, float]
"""``(longitude, latitude)`` in degrees, in that order — GeoJSON's order, not Apple's."""


@dataclass(frozen=True)
class BoundingBox:
    """A longitude/latitude envelope in degrees."""

    west: float
    south: float
    east: float
    north: float

    @classmethod
    def around(cls, coordinates: Iterable[Coordinate]) -> BoundingBox:
        longitudes: list[float] = []
        latitudes: list[float] = []
        for longitude, latitude in coordinates:
            longitudes.append(longitude)
            latitudes.append(latitude)
        if not longitudes:
            raise ValueError("a bounding box needs at least one coordinate")
        return cls(min(longitudes), min(latitudes), max(longitudes), max(latitudes))

    def union(self, other: BoundingBox) -> BoundingBox:
        return BoundingBox(
            min(self.west, other.west),
            min(self.south, other.south),
            max(self.east, other.east),
            max(self.north, other.north),
        )

    def buffered(self, metres: float) -> BoundingBox:
        """Grow the box by a ground distance, not by a number of degrees.

        Each edge converts the distance with the radius of curvature that applies to it,
        and the longitude padding uses the latitude that needs the most of it — the edge
        furthest from the equator — so the box grows by *at least* ``metres`` everywhere.
        """
        south_padding = math.degrees(metres / meridional_radius_m(self.south))
        north_padding = math.degrees(metres / meridional_radius_m(self.north))
        widest = min(max(abs(self.north), abs(self.south)), MERCATOR_MAX_LATITUDE)
        east_west_radius = prime_vertical_radius_m(widest) * math.cos(math.radians(widest))
        longitude_padding = math.degrees(metres / max(east_west_radius, 1.0))
        return BoundingBox(
            self.west - longitude_padding,
            max(self.south - south_padding, -MERCATOR_MAX_LATITUDE),
            self.east + longitude_padding,
            min(self.north + north_padding, MERCATOR_MAX_LATITUDE),
        )

    @property
    def centre(self) -> Coordinate:
        return ((self.west + self.east) / 2.0, (self.south + self.north) / 2.0)

    def as_list(self) -> list[float]:
        """``[west, south, east, north]`` — the order GeoJSON and MBTiles both use."""
        return [self.west, self.south, self.east, self.north]


def meridional_radius_m(latitude_degrees: float) -> float:
    """Radius of curvature along the meridian (north–south) at this latitude."""
    sine = math.sin(math.radians(latitude_degrees))
    return (
        EARTH_SEMI_MAJOR_M
        * (1.0 - ECCENTRICITY_SQUARED)
        / (1.0 - ECCENTRICITY_SQUARED * sine * sine) ** 1.5
    )


def prime_vertical_radius_m(latitude_degrees: float) -> float:
    """Radius of curvature perpendicular to the meridian (east–west)."""
    sine = math.sin(math.radians(latitude_degrees))
    return EARTH_SEMI_MAJOR_M / math.sqrt(1.0 - ECCENTRICITY_SQUARED * sine * sine)


def distance_m(start: Coordinate, end: Coordinate) -> float:
    """Ground distance between two nearby points on the WGS84 ellipsoid.

    The local tangent-plane formula: the ellipsoid's two radii of curvature are taken at
    the midpoint latitude and the step is treated as flat. Over a trail vertex spacing of
    metres to hundreds of metres that is accurate to far better than the elevation data
    behind it, and it is cheap enough to run on every one of a park's hundred thousand
    resampled stations.

    It is *not* a general geodesic: it is only used on short steps, which is all a route
    line is made of.
    """
    start_longitude, start_latitude = start
    end_longitude, end_latitude = end
    mid_latitude = (start_latitude + end_latitude) / 2.0
    delta_latitude = math.radians(end_latitude - start_latitude)
    delta_longitude = math.radians(_wrap_longitude(end_longitude - start_longitude))
    northing = meridional_radius_m(mid_latitude) * delta_latitude
    easting = (
        prime_vertical_radius_m(mid_latitude)
        * math.cos(math.radians(mid_latitude))
        * delta_longitude
    )
    return math.hypot(easting, northing)


def line_length_m(line: Sequence[Coordinate]) -> float:
    """Length of a polyline along the ground.

    Horizontal (map) length, which is what a trail sign and a guidebook quote. The
    slope-following length is ``measure.slope_length_m``, and the two are reported
    separately rather than silently mixed.
    """
    return sum(distance_m(line[index], line[index + 1]) for index in range(len(line) - 1))


def ring_area_m2(ring: Sequence[Coordinate]) -> float:
    """Unsigned area of a closed ring, on the authalic sphere.

    L'Huilier is numerically fragile for the long thin triangles a park boundary
    produces, so this is the standard line-integral form, which only needs the ring's
    vertices to be in order.
    """
    if len(ring) < 4:
        return 0.0
    total = 0.0
    for index in range(len(ring) - 1):
        longitude_1, latitude_1 = ring[index]
        longitude_2, latitude_2 = ring[index + 1]
        total += math.radians(_wrap_longitude(longitude_2 - longitude_1)) * (
            2.0
            + math.sin(math.radians(latitude_1))
            + math.sin(math.radians(latitude_2))
        )
    return abs(total * EARTH_AUTHALIC_RADIUS_M * EARTH_AUTHALIC_RADIUS_M / 2.0)


def _wrap_longitude(degrees: float) -> float:
    """Shortest signed longitude difference, so a park on the antimeridian still works."""
    wrapped = (degrees + 180.0) % 360.0 - 180.0
    return wrapped


# --- Web Mercator ------------------------------------------------------------------


def to_mercator(longitude: float, latitude: float) -> tuple[float, float]:
    clamped = max(min(latitude, MERCATOR_MAX_LATITUDE), -MERCATOR_MAX_LATITUDE)
    x = math.radians(longitude) * MERCATOR_RADIUS_M
    y = math.log(math.tan(math.pi / 4.0 + math.radians(clamped) / 2.0)) * MERCATOR_RADIUS_M
    return x, y


def from_mercator(x: float, y: float) -> Coordinate:
    longitude = math.degrees(x / MERCATOR_RADIUS_M)
    latitude = math.degrees(2.0 * math.atan(math.exp(y / MERCATOR_RADIUS_M)) - math.pi / 2.0)
    return longitude, latitude


def mercator_scale_at(latitude_degrees: float) -> float:
    """How much Web Mercator stretches distance at this latitude (always ≥ 1).

    One Mercator metre is ``cos(latitude)`` ground metres, so the hillshade divides by
    this before it calls a slope a slope.
    """
    clamped = max(min(latitude_degrees, MERCATOR_MAX_LATITUDE), -MERCATOR_MAX_LATITUDE)
    return 1.0 / max(math.cos(math.radians(clamped)), 1e-6)


def tile_count(zoom: int) -> int:
    return 1 << zoom


def tile_span_m(zoom: int) -> float:
    """Width of one tile in Mercator metres."""
    return 2.0 * MERCATOR_ORIGIN_SHIFT_M / tile_count(zoom)


def tile_resolution_m_per_pixel(zoom: int, latitude_degrees: float, tile_size: int = 256) -> float:
    """Ground metres per pixel — the number that decides whether a zoom is worth having."""
    return tile_span_m(zoom) / tile_size / mercator_scale_at(latitude_degrees)


def tile_for_coordinate(longitude: float, latitude: float, zoom: int) -> tuple[int, int]:
    """XYZ tile containing a point. ``y`` counts down from the north, as XYZ does."""
    count = tile_count(zoom)
    x_fraction = (longitude + 180.0) / 360.0
    clamped = max(min(latitude, MERCATOR_MAX_LATITUDE), -MERCATOR_MAX_LATITUDE)
    sine = math.sin(math.radians(clamped))
    y_fraction = 0.5 - math.log((1.0 + sine) / (1.0 - sine)) / (4.0 * math.pi)
    x = min(max(int(x_fraction * count), 0), count - 1)
    y = min(max(int(y_fraction * count), 0), count - 1)
    return x, y


def tile_mercator_bounds(zoom: int, x: int, y: int) -> tuple[float, float, float, float]:
    """``(min_x, min_y, max_x, max_y)`` of a tile in Mercator metres."""
    span = tile_span_m(zoom)
    min_x = -MERCATOR_ORIGIN_SHIFT_M + x * span
    max_y = MERCATOR_ORIGIN_SHIFT_M - y * span
    return min_x, max_y - span, min_x + span, max_y


def tile_bounds(zoom: int, x: int, y: int) -> BoundingBox:
    min_x, min_y, max_x, max_y = tile_mercator_bounds(zoom, x, y)
    west, south = from_mercator(min_x, min_y)
    east, north = from_mercator(max_x, max_y)
    return BoundingBox(west, south, east, north)


def tile_range(box: BoundingBox, zoom: int) -> tuple[int, int, int, int]:
    """``(min_x, min_y, max_x, max_y)`` tile indices covering a box, inclusive."""
    min_x, min_y = tile_for_coordinate(box.west, box.north, zoom)
    max_x, max_y = tile_for_coordinate(box.east, box.south, zoom)
    return min_x, min_y, max_x, max_y


def flip_tile_row(zoom: int, y: int) -> int:
    """XYZ row to the TMS row MBTiles stores, and back again — it is its own inverse."""
    return tile_count(zoom) - 1 - y
