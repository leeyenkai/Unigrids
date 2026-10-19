"""The elevation grid: reading it, sampling it, and shading it.

One grid per park, in Web Mercator metres, assembled from the chunks ``fetch`` downloaded.
Everything elevation-shaped in a pack comes through here — the trail profiles and the
hillshade both — so a trail's stated climb and the relief it is drawn over cannot
disagree.
"""

from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np
import tifffile

from .geo import mercator_scale_at, to_mercator

NO_DATA_FLOOR = -1e5
"""Anything below this is the service's nodata fill, not a depth below sea level."""


class ElevationGrid:
    """A float32 elevation raster with its Mercator georeferencing.

    Pixel ``(row, column)`` covers Mercator metres
    ``x ∈ [origin_x + column·p, origin_x + (column+1)·p]`` and
    ``y ∈ [origin_y − (row+1)·p, origin_y − row·p]``, so its centre is half a pixel in
    from the corner. Sampling is bilinear between pixel centres; missing data stays
    ``NaN`` and propagates, because an interpolated value next to a hole is a guess.
    """

    def __init__(
        self,
        values: np.ndarray,
        origin_x: float,
        origin_y: float,
        pixel_size: float,
        *,
        ground_resolution_m: float | None = None,
    ) -> None:
        self.values = values
        self.origin_x = origin_x
        self.origin_y = origin_y
        self.pixel_size = pixel_size
        self.ground_resolution_m = ground_resolution_m or pixel_size
        self.rows, self.columns = values.shape

    @classmethod
    def load(cls, directory: Path) -> ElevationGrid:
        """Assemble the grid from ``index.json`` and its chunks."""
        index = json.loads((directory / "index.json").read_text())
        values = np.full((index["rows"], index["columns"]), np.nan, dtype=np.float32)
        for chunk in index["chunks"]:
            patch = tifffile.imread(directory / chunk["file"])
            patch = np.asarray(patch, dtype=np.float32)
            if patch.ndim == 3:
                patch = patch[..., 0]
            row, column = chunk["row"], chunk["column"]
            height = min(chunk["rows"], patch.shape[0])
            width = min(chunk["columns"], patch.shape[1])
            values[row : row + height, column : column + width] = patch[:height, :width]
        values[values <= NO_DATA_FLOOR] = np.nan
        return cls(
            values,
            index["origin_x"],
            index["origin_y"],
            index["pixel_size"],
            ground_resolution_m=index.get("ground_resolution_m"),
        )

    @property
    def coverage(self) -> float:
        return float(np.isfinite(self.values).mean())

    def sample_mercator(self, x: np.ndarray, y: np.ndarray) -> np.ndarray:
        """Bilinear elevation at Mercator coordinates. Outside the grid gives ``NaN``."""
        column = (np.asarray(x, dtype=np.float64) - self.origin_x) / self.pixel_size - 0.5
        row = (self.origin_y - np.asarray(y, dtype=np.float64)) / self.pixel_size - 0.5

        column_0 = np.floor(column)
        row_0 = np.floor(row)
        fraction_x = column - column_0
        fraction_y = row - row_0

        inside = (
            (column_0 >= 0)
            & (row_0 >= 0)
            & (column_0 <= self.columns - 2)
            & (row_0 <= self.rows - 2)
        )
        column_index = np.clip(column_0.astype(np.int64), 0, max(self.columns - 2, 0))
        row_index = np.clip(row_0.astype(np.int64), 0, max(self.rows - 2, 0))

        top_left = self.values[row_index, column_index]
        top_right = self.values[row_index, column_index + 1]
        bottom_left = self.values[row_index + 1, column_index]
        bottom_right = self.values[row_index + 1, column_index + 1]

        top = top_left + (top_right - top_left) * fraction_x
        bottom = bottom_left + (bottom_right - bottom_left) * fraction_x
        sampled = top + (bottom - top) * fraction_y
        return np.where(inside, sampled, np.nan)

    def sample(self, longitude: float, latitude: float) -> float | None:
        """One point, in degrees — the shape ``measure.ElevationSampler`` expects."""
        x, y = to_mercator(longitude, latitude)
        value = float(self.sample_mercator(np.array([x]), np.array([y]))[0])
        return None if math.isnan(value) else value

    def sample_many(
        self, longitudes: np.ndarray, latitudes: np.ndarray
    ) -> np.ndarray:
        """Vectorised degree sampling, for a whole trail's worth of stations at once."""
        clamped = np.clip(np.asarray(latitudes, dtype=np.float64), -85.05, 85.05)
        x = np.radians(np.asarray(longitudes, dtype=np.float64)) * 6378137.0
        y = np.log(np.tan(np.pi / 4.0 + np.radians(clamped) / 2.0)) * 6378137.0
        return self.sample_mercator(x, y)

    def patch(
        self, min_x: float, min_y: float, max_x: float, max_y: float, width: int, height: int
    ) -> np.ndarray:
        """Resample a Mercator window onto a ``height × width`` array of pixel centres."""
        x_step = (max_x - min_x) / width
        y_step = (max_y - min_y) / height
        x = min_x + (np.arange(width) + 0.5) * x_step
        y = max_y - (np.arange(height) + 0.5) * y_step
        grid_x, grid_y = np.meshgrid(x, y)
        return self.sample_mercator(grid_x, grid_y)


def hillshade(
    elevation: np.ndarray,
    pixel_size_mercator_m: float,
    latitude_degrees: float,
    *,
    azimuth_degrees: float = 315.0,
    altitude_degrees: float = 45.0,
    vertical_exaggeration: float = 1.6,
) -> np.ndarray:
    """Relief shading in 0.0–1.0, from the north-west as every map since Swiss topos.

    The pixel size is divided by the Mercator stretch first: Mercator metres are longer
    than ground metres by ``1 / cos(latitude)``, and shading as if they were not would make
    every park look flatter the further north it is.

    The vertical exaggeration is a cartographic choice, not a correction — a touch of it is
    what makes a canyon read as a canyon at a park-wide zoom.
    """
    ground_pixel = max(pixel_size_mercator_m / mercator_scale_at(latitude_degrees), 1e-6)
    filled = np.where(np.isfinite(elevation), elevation, np.nanmean(elevation))
    if not np.isfinite(filled).any():
        return np.full(elevation.shape, 0.5, dtype=np.float32)
    filled = np.nan_to_num(filled, nan=0.0)

    d_row, d_column = np.gradient(filled * vertical_exaggeration, ground_pixel)
    # Row index grows southwards, so the north–south slope is the negative of the gradient.
    slope = np.arctan(np.hypot(d_column, -d_row))
    aspect = np.arctan2(-d_row, -d_column)

    azimuth = np.radians(360.0 - azimuth_degrees + 90.0)
    altitude = np.radians(altitude_degrees)
    shaded = np.sin(altitude) * np.cos(slope) + np.cos(altitude) * np.sin(slope) * np.cos(
        azimuth - aspect
    )
    return np.clip(shaded, 0.0, 1.0).astype(np.float32)
