"""Which tiles a park's pack contains.

A park is not its bounding box. Zion's outline is two canyons joined by a thin waist, and
the box around it is nearly three times the park's area — so rendering the box would spend
most of the pack on ground nobody is in the park to see. Tiles are therefore chosen
against the boundary itself, grown by
:attr:`~unigrids_pipeline.config.PackSettings.boundary_buffer_m` so the approach roads, the
gateway town and a trailhead just outside the line are still on the map.

The boundary is rasterised once into a coarse mask in Web Mercator, and each zoom's tiles
are read off that mask. The same code answers both questions the pilot asks: which tiles
to render for Zion, and — run over all 63 parks' outlines — how many tiles the other 62
would come to.
"""

from __future__ import annotations

from collections.abc import Iterable, Iterator, Sequence
from dataclasses import dataclass
from typing import Any

import numpy as np
from PIL import Image, ImageDraw

from .geo import (
    MERCATOR_ORIGIN_SHIFT_M,
    BoundingBox,
    Coordinate,
    ring_area_m2,
    tile_count,
    tile_range,
    tile_span_m,
    to_mercator,
)

MASK_CELLS_PER_TILE = 4
"""Mask resolution, in cells across a tile at the pack's deepest zoom. Four is enough to
keep a tile that only clips the park's edge, and coarse enough that a park the size of
Wrangell–St. Elias still rasterises into a few megabytes."""

MAX_MASK_DIMENSION = 6000
"""A ceiling for the largest parks: the mask coarsens rather than the memory growing."""


@dataclass(frozen=True)
class Ring:
    coordinates: list[Coordinate]
    is_hole: bool


def rings(features: Iterable[dict[str, Any]]) -> list[Ring]:
    """Exterior rings and holes out of GeoJSON polygons.

    GeoJSON puts the exterior ring first in each polygon and the holes after it, which is
    the only ordering this needs — winding direction is not relied on.
    """
    collected: list[Ring] = []
    for feature in features:
        geometry = feature.get("geometry") or {}
        kind = geometry.get("type")
        if kind == "Polygon":
            polygons = [geometry.get("coordinates") or []]
        elif kind == "MultiPolygon":
            polygons = geometry.get("coordinates") or []
        else:
            continue
        for polygon in polygons:
            for index, ring in enumerate(polygon):
                if len(ring) >= 4:
                    collected.append(
                        Ring([(float(point[0]), float(point[1])) for point in ring], index > 0)
                    )
    return collected


def area_km2(boundary_rings: Sequence[Ring]) -> float:
    """Land area inside the boundary, holes taken out, on the authalic sphere."""
    total = 0.0
    for ring in boundary_rings:
        area = ring_area_m2(ring.coordinates)
        total += -area if ring.is_hole else area
    return max(total, 0.0) / 1e6


class ParkCoverage:
    """A park's outline, as a mask that tile lists are read off."""

    def __init__(
        self,
        boundary_rings: Sequence[Ring],
        *,
        buffer_m: float,
        max_zoom: int,
        extra: BoundingBox | None = None,
    ) -> None:
        if not boundary_rings:
            raise ValueError("a park needs at least one boundary ring")
        self.rings = list(boundary_rings)
        self.buffer_m = buffer_m
        self.area_km2 = area_km2(self.rings)

        self.bounds = BoundingBox.around(
            point for ring in self.rings if not ring.is_hole for point in ring.coordinates
        )
        if extra is not None:
            self.bounds = self.bounds.union(extra)
        self.render_bounds = self.bounds.buffered(buffer_m)

        min_x, min_y = to_mercator(self.render_bounds.west, self.render_bounds.south)
        max_x, max_y = to_mercator(self.render_bounds.east, self.render_bounds.north)
        wanted = tile_span_m(max_zoom) / MASK_CELLS_PER_TILE
        longest = max(max_x - min_x, max_y - min_y)
        self.cell_size = max(wanted, longest / MAX_MASK_DIMENSION)
        self.columns = max(1, int(np.ceil((max_x - min_x) / self.cell_size)))
        self.rows = max(1, int(np.ceil((max_y - min_y) / self.cell_size)))
        self.origin_x = min_x
        self.origin_y = min_y + self.rows * self.cell_size
        self.mask = self._rasterise()

    def _rasterise(self) -> np.ndarray:
        """Fill the rings, then thicken their outlines to apply the buffer.

        Drawing the outline with a brush ``2 × buffer`` wide is a square-ended
        approximation of a proper buffer. At 150-metre cells against a 2 km buffer the
        difference is a cell or two of ground on the park's edge, which is far inside the
        precision the boundary itself has.
        """
        image = Image.new("L", (self.columns, self.rows), 0)
        draw = ImageDraw.Draw(image)
        buffer_cells = max(1, round(self.buffer_m / self.cell_size))

        for ring in self.rings:
            if ring.is_hole:
                continue
            points = [self._cell_of(*point) for point in ring.coordinates]
            draw.polygon(points, fill=255)
            if buffer_cells > 0:
                draw.line(points, fill=255, width=buffer_cells * 2, joint="curve")

        # Holes are cut after the fill, and shrunk by the buffer: ground within the buffer
        # of the park is kept even where it falls in an inholding.
        for ring in self.rings:
            if not ring.is_hole:
                continue
            points = [self._cell_of(*point) for point in ring.coordinates]
            draw.polygon(points, fill=0)
            if buffer_cells > 0:
                draw.line(points, fill=255, width=buffer_cells * 2, joint="curve")

        return np.array(image, dtype=np.uint8) > 0

    def _cell_of(self, longitude: float, latitude: float) -> tuple[float, float]:
        x, y = to_mercator(longitude, latitude)
        return (
            (x - self.origin_x) / self.cell_size,
            (self.origin_y - y) / self.cell_size,
        )

    def tiles(self, zoom: int) -> list[tuple[int, int]]:
        """XYZ ``(x, y)`` tiles whose ground overlaps the buffered park, sorted."""
        rows, columns = np.nonzero(self.mask)
        if rows.size == 0:
            return []
        cell_x = self.origin_x + (columns + 0.5) * self.cell_size
        cell_y = self.origin_y - (rows + 0.5) * self.cell_size
        span = tile_span_m(zoom)
        limit = tile_count(zoom) - 1
        tile_x = np.clip(
            np.floor((cell_x + MERCATOR_ORIGIN_SHIFT_M) / span).astype(np.int64), 0, limit
        )
        tile_y = np.clip(
            np.floor((MERCATOR_ORIGIN_SHIFT_M - cell_y) / span).astype(np.int64), 0, limit
        )
        pairs = np.unique(np.stack([tile_x, tile_y], axis=1), axis=0)
        return [(int(x), int(y)) for x, y in pairs]

    def tile_counts(self, zooms: Iterable[int]) -> dict[int, int]:
        return {zoom: len(self.tiles(zoom)) for zoom in zooms}

    def all_tiles(self, zooms: Iterable[int]) -> Iterator[tuple[int, int, int]]:
        for zoom in zooms:
            for x, y in self.tiles(zoom):
                yield zoom, x, y

    def bounding_box_tile_counts(self, zooms: Iterable[int]) -> dict[int, int]:
        """What the same zooms would cost for the whole bounding box.

        Reported next to the clipped counts, because the gap is the single biggest saving
        in the pack and worth being able to see.
        """
        counts = {}
        for zoom in zooms:
            min_x, min_y, max_x, max_y = tile_range(self.render_bounds, zoom)
            counts[zoom] = (max_x - min_x + 1) * (max_y - min_y + 1)
        return counts
