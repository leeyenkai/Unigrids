"""Rendering one tile of a park pack.

A tile is relief-shaded terrain from the elevation grid with water, roads, trails and the
park boundary drawn over it. Three choices in here are worth knowing about, because each
one is visible in the size report:

* **Vectors are drawn at twice the tile size and scaled down**, which is what makes a
  dashed trail look like a line rather than a staircase. It also costs bytes: anti-aliased
  edges give a PNG more colours to encode than hard ones.
* **OSM paths and footways are not drawn.** The NPS trails dataset is the trail source
  (§8), and drawing both would print most trails twice, half a pixel apart.
* **Tiles are encoded three ways on request** — PNG, 256-colour PNG, WebP — because
  "which format" is one of the levers the 4 GB question turns on, and a lever is worth
  measuring rather than arguing about.
"""

from __future__ import annotations

import io
import math
from collections import defaultdict
from collections.abc import Iterable, Sequence
from dataclasses import dataclass, field
from typing import Any

import numpy as np
from PIL import Image, ImageDraw

from . import style
from .dem import ElevationGrid, hillshade
from .geo import (
    MERCATOR_ORIGIN_SHIFT_M,
    BoundingBox,
    Coordinate,
    from_mercator,
    tile_count,
    tile_mercator_bounds,
    tile_span_m,
    to_mercator,
)

SUPERSAMPLE = 2
"""Draw the vector layer at this multiple of the tile size, then scale down."""

# OSM highway values, grouped into the three weights the style draws. Paths, footways,
# cycleways, bridleways and steps are deliberately absent: those are trails, and trails
# come from the NPS dataset.
ROAD_CLASSES = {
    "motorway": "major",
    "motorway_link": "major",
    "trunk": "major",
    "trunk_link": "major",
    "primary": "major",
    "primary_link": "major",
    "secondary": "major",
    "secondary_link": "major",
    "tertiary": "minor",
    "tertiary_link": "minor",
    "unclassified": "minor",
    "residential": "minor",
    "living_street": "minor",
    "service": "track",
    "track": "track",
    "road": "minor",
}

WATER_AREA_TAGS = (
    ("natural", "water"),
    ("landuse", "reservoir"),
    ("natural", "wetland"),
)


@dataclass(frozen=True)
class Shape:
    """One drawable line or ring, in longitude/latitude."""

    kind: str
    coordinates: list[Coordinate]
    box: BoundingBox

    @classmethod
    def of(cls, kind: str, coordinates: Sequence[Coordinate]) -> Shape | None:
        cleaned = [(float(point[0]), float(point[1])) for point in coordinates]
        if len(cleaned) < 2:
            return None
        return cls(kind, cleaned, BoundingBox.around(cleaned))


@dataclass
class VectorLayers:
    """Everything drawn over the terrain, bucketed by tile when a zoom asks for it."""

    water_areas: list[Shape] = field(default_factory=list)
    water_lines: list[Shape] = field(default_factory=list)
    roads: list[Shape] = field(default_factory=list)
    trails: list[Shape] = field(default_factory=list)
    boundary: list[Shape] = field(default_factory=list)
    _indices: dict[int, dict[tuple[int, int], list[Shape]]] = field(default_factory=dict)

    @property
    def all_shapes(self) -> list[Shape]:
        return self.water_areas + self.water_lines + self.roads + self.trails + self.boundary

    def counts(self) -> dict[str, int]:
        return {
            "water_areas": len(self.water_areas),
            "water_lines": len(self.water_lines),
            "roads": len(self.roads),
            "trails": len(self.trails),
            "boundary": len(self.boundary),
        }

    def index(self, zoom: int) -> dict[tuple[int, int], list[Shape]]:
        """Which shapes touch which tile at this zoom.

        Built once per zoom. A shape is listed against every tile its bounding box
        overlaps, so a road that crosses a tile without having a vertex in it is still
        drawn — the alternative is roads that stop at tile edges.
        """
        if zoom in self._indices:
            return self._indices[zoom]
        buckets: dict[tuple[int, int], list[Shape]] = defaultdict(list)
        span = tile_span_m(zoom)
        limit = tile_count(zoom) - 1
        for shape in self.all_shapes:
            min_x, min_y = to_mercator(shape.box.west, shape.box.south)
            max_x, max_y = to_mercator(shape.box.east, shape.box.north)
            first_x = max(0, min(limit, int((min_x + MERCATOR_ORIGIN_SHIFT_M) // span)))
            last_x = max(0, min(limit, int((max_x + MERCATOR_ORIGIN_SHIFT_M) // span)))
            first_y = max(0, min(limit, int((MERCATOR_ORIGIN_SHIFT_M - max_y) // span)))
            last_y = max(0, min(limit, int((MERCATOR_ORIGIN_SHIFT_M - min_y) // span)))
            for x in range(first_x, last_x + 1):
                for y in range(first_y, last_y + 1):
                    buckets[(x, y)].append(shape)
        self._indices[zoom] = buckets
        return buckets

    def forget_index(self, zoom: int) -> None:
        self._indices.pop(zoom, None)


def layers_from_sources(
    osm_ways: Iterable[dict[str, Any]],
    trail_features: Iterable[dict[str, Any]],
    boundary_features: Iterable[dict[str, Any]],
) -> VectorLayers:
    """Sort the fetched sources into the things the style knows how to draw."""
    layers = VectorLayers()

    for way in osm_ways:
        tags = way.get("tags") or {}
        geometry = way.get("geometry") or []
        coordinates = [
            (point["lon"], point["lat"])
            for point in geometry
            if point.get("lon") is not None and point.get("lat") is not None
        ]
        if len(coordinates) < 2:
            continue
        if any(tags.get(key) == value for key, value in WATER_AREA_TAGS):
            shape = Shape.of("water_area", coordinates)
            if shape:
                layers.water_areas.append(shape)
            continue
        if tags.get("waterway"):
            shape = Shape.of("water_line", coordinates)
            if shape:
                layers.water_lines.append(shape)
            continue
        road_class = ROAD_CLASSES.get(tags.get("highway", ""))
        if road_class:
            shape = Shape.of(road_class, coordinates)
            if shape:
                layers.roads.append(shape)

    for feature in trail_features:
        for line in _lines_of(feature.get("geometry") or {}):
            shape = Shape.of("trail", line)
            if shape:
                layers.trails.append(shape)

    for feature in boundary_features:
        geometry = feature.get("geometry") or {}
        kind = geometry.get("type")
        polygons = []
        if kind == "Polygon":
            polygons = [geometry.get("coordinates") or []]
        elif kind == "MultiPolygon":
            polygons = geometry.get("coordinates") or []
        for polygon in polygons:
            for ring in polygon:
                shape = Shape.of("boundary", ring)
                if shape:
                    layers.boundary.append(shape)

    # Longest first, so a major road is drawn over the service road it joins.
    layers.roads.sort(key=lambda shape: -len(shape.coordinates))
    return layers


def _lines_of(geometry: dict[str, Any]) -> list[list[Coordinate]]:
    kind = geometry.get("type")
    if kind == "LineString":
        return [geometry.get("coordinates") or []]
    if kind == "MultiLineString":
        return list(geometry.get("coordinates") or [])
    return []


class TileRenderer:
    """Renders tiles for one park. Holds the elevation grid and the vector index."""

    def __init__(
        self,
        grid: ElevationGrid,
        layers: VectorLayers,
        *,
        tile_size: int = 256,
        supersample: int = SUPERSAMPLE,
    ) -> None:
        self.grid = grid
        self.layers = layers
        self.tile_size = tile_size
        self.supersample = max(1, supersample)

    def render(self, zoom: int, x: int, y: int) -> Image.Image:
        terrain = self._terrain(zoom, x, y)
        overlay = self._overlay(zoom, x, y)
        if overlay is not None:
            terrain = Image.alpha_composite(terrain.convert("RGBA"), overlay).convert("RGB")
        return terrain

    def _terrain(self, zoom: int, x: int, y: int) -> Image.Image:
        """Relief-shaded land for one tile.

        Two details decide whether this looks like a map or like a rendering bug.

        The elevation patch is a pixel wider on every side than the tile, because the
        hillshade is a gradient: without the halo every tile comes out with a seam of wrong
        shading around its edge.

        And **the shading is never computed finer than the elevation model is**. Past about
        zoom 14 a tile pixel is smaller than 3DEP's 10 m posting, and shading the
        interpolated grid at tile resolution turns the creases between interpolated facets
        into hard terraces — detail that is not in the data, looks like corduroy, and costs
        a fortune to encode because it is all high-frequency edges. So the shading is
        computed at the model's own resolution and scaled up smoothly, which is both
        honest and smaller.
        """
        min_x, min_y, max_x, max_y = tile_mercator_bounds(zoom, x, y)
        size = self.tile_size
        pixel = (max_x - min_x) / size
        _, centre_latitude = from_mercator((min_x + max_x) / 2.0, (min_y + max_y) / 2.0)

        shade_size = size
        shade_pixel = pixel
        if pixel < self.grid.pixel_size:
            shade_size = max(16, round((max_x - min_x) / self.grid.pixel_size))
            shade_pixel = (max_x - min_x) / shade_size

        shade_patch = self.grid.patch(
            min_x - shade_pixel,
            min_y - shade_pixel,
            max_x + shade_pixel,
            max_y + shade_pixel,
            shade_size + 2,
            shade_size + 2,
        )
        shaded = hillshade(shade_patch, shade_pixel, centre_latitude)[1:-1, 1:-1]
        if shade_size != size:
            shaded = np.asarray(
                Image.fromarray(shaded, mode="F").resize(
                    (size, size), resample=Image.Resampling.BILINEAR
                ),
                dtype=np.float32,
            )

        patch = self.grid.patch(min_x, min_y, max_x, max_y, size, size)
        pixels = style.shade(style.land_tint(patch), shaded)
        return Image.fromarray(pixels, mode="RGB")

    def _overlay(self, zoom: int, x: int, y: int) -> Image.Image | None:
        shapes = self.layers.index(zoom).get((x, y))
        if not shapes:
            return None

        scale = self.supersample
        size = self.tile_size * scale
        min_x, _, max_x, max_y = tile_mercator_bounds(zoom, x, y)
        span = max_x - min_x
        overlay = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        draw = ImageDraw.Draw(overlay)

        def to_pixels(shape: Shape) -> list[tuple[float, float]]:
            points: list[tuple[float, float]] = []
            for longitude, latitude in shape.coordinates:
                point_x, point_y = to_mercator(longitude, latitude)
                points.append(
                    (
                        (point_x - min_x) / span * size,
                        (max_y - point_y) / span * size,
                    )
                )
            return _thin(points, 0.7 * scale)

        grouped: dict[str, list[list[tuple[float, float]]]] = defaultdict(list)
        for shape in shapes:
            grouped[shape.kind].append(to_pixels(shape))

        for ring in grouped.get("water_area", []):
            if len(ring) >= 3:
                draw.polygon(ring, fill=(*style.WATER_FILL, 255))
        for ring in grouped.get("water_area", []):
            _stroke(draw, ring, style.WATER_EDGE_STYLE, zoom, scale)
        for line in grouped.get("water_line", []):
            _stroke(draw, line, style.WATER_LINE_STYLE, zoom, scale)

        for weight in ("track", "minor", "major"):
            line_style = style.ROAD_STYLES[weight]
            for line in grouped.get(weight, []):
                _stroke(draw, line, line_style, zoom, scale, casing_only=True)
        for weight in ("track", "minor", "major"):
            line_style = style.ROAD_STYLES[weight]
            for line in grouped.get(weight, []):
                _stroke(draw, line, line_style, zoom, scale)

        for line in grouped.get("boundary", []):
            _stroke(draw, line, style.BOUNDARY_STYLE, zoom, scale)
        for line in grouped.get("trail", []):
            _stroke(draw, line, style.TRAIL_STYLE, zoom, scale)

        if scale > 1:
            overlay = overlay.resize(
                (self.tile_size, self.tile_size), resample=Image.Resampling.LANCZOS
            )
        return overlay


def _stroke(
    draw: ImageDraw.ImageDraw,
    points: Sequence[tuple[float, float]],
    line_style: style.LineStyle,
    zoom: int,
    scale: int,
    *,
    casing_only: bool = False,
) -> None:
    if len(points) < 2 or zoom < line_style.min_zoom:
        return
    if casing_only:
        if line_style.casing_colour is None:
            return
        colour = (*line_style.casing_colour, 255)
        width = (line_style.width(zoom) + line_style.casing_extra_width) * scale
    else:
        colour = (*line_style.colour, 255)
        width = line_style.width(zoom) * scale

    pixel_width = max(1, round(width))
    if line_style.dash_pattern and not casing_only:
        on, off = (length * scale for length in line_style.dash_pattern)
        for dash in _dashes(points, on, off):
            draw.line(dash, fill=colour, width=pixel_width, joint="curve")
        return
    draw.line(list(points), fill=colour, width=pixel_width, joint="curve")


def _dashes(
    points: Sequence[tuple[float, float]], on: float, off: float
) -> list[list[tuple[float, float]]]:
    """Split a polyline into dashes by pixel length, since PIL has no dash support."""
    period = on + off
    if period <= 0:
        return [list(points)]
    dashes: list[list[tuple[float, float]]] = []
    current: list[tuple[float, float]] = []
    travelled = 0.0

    for index in range(len(points) - 1):
        start = points[index]
        end = points[index + 1]
        length = math.dist(start, end)
        if length <= 0:
            continue
        position = 0.0
        while position < length:
            phase = travelled % period
            drawing = phase < on
            remaining = (on - phase) if drawing else (period - phase)
            step = min(remaining, length - position)
            from_point = _along(start, end, position / length)
            to_point = _along(start, end, (position + step) / length)
            if drawing:
                if current and current[-1] == from_point:
                    current.append(to_point)
                else:
                    if len(current) >= 2:
                        dashes.append(current)
                    current = [from_point, to_point]
            elif len(current) >= 2:
                dashes.append(current)
                current = []
            else:
                current = []
            position += step
            travelled += step
    if len(current) >= 2:
        dashes.append(current)
    return dashes


def _along(
    start: tuple[float, float], end: tuple[float, float], fraction: float
) -> tuple[float, float]:
    return (
        start[0] + (end[0] - start[0]) * fraction,
        start[1] + (end[1] - start[1]) * fraction,
    )


def _thin(
    points: Sequence[tuple[float, float]], minimum_spacing: float
) -> list[tuple[float, float]]:
    """Drop vertices closer together than a pixel.

    At a park-wide zoom a trail's 10-metre digitising detail is a hundred vertices inside
    one pixel. Dropping them changes nothing on screen and is most of the drawing time at
    low zoom.
    """
    if len(points) < 3:
        return list(points)
    thinned = [points[0]]
    for point in points[1:-1]:
        if math.dist(point, thinned[-1]) >= minimum_spacing:
            thinned.append(point)
    thinned.append(points[-1])
    return thinned


def encode(image: Image.Image, tile_format: str, *, webp_quality: int = 82) -> bytes:
    """Encode a tile. ``png``, ``png8`` (256-colour, dithered) or ``webp``."""
    buffer = io.BytesIO()
    if tile_format == "png":
        image.save(buffer, format="PNG", optimize=True)
    elif tile_format == "png8":
        quantised = image.convert(
            "P", palette=Image.Palette.ADAPTIVE, colors=256, dither=Image.Dither.FLOYDSTEINBERG
        )
        quantised.save(buffer, format="PNG", optimize=True)
    elif tile_format == "webp":
        image.save(buffer, format="WEBP", quality=webp_quality, method=4)
    else:
        raise ValueError(f"unknown tile format {tile_format!r}: expected png, png8 or webp")
    return buffer.getvalue()


def mime_type(tile_format: str) -> str:
    return {"png": "image/png", "png8": "image/png", "webp": "image/webp"}[tile_format]

