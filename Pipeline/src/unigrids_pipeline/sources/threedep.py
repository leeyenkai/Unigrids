"""USGS 3DEP elevation, fetched as a float32 raster for one park's extent.

3DEP is public domain (``SPECIFICATION.md`` §12) and the national map's dynamic image
service will hand back a window of it at whatever resolution is asked for. That matters
for two reasons: the trail profiles need elevation *along* the route lines, and the tiles
need a hillshade — and both have to come from the same grid, or a trail's profile would
disagree with the relief it is drawn on.

The download is one regular grid in Web Mercator metres, split into chunks under the
service's 8000-pixel limit, plus an ``index.json`` giving the grid's origin and pixel
size. Writing the grid down means no GeoTIFF tags have to be parsed back: the pipeline
chose the window, so it already knows where every pixel is.
"""

from __future__ import annotations

import json
import math
from pathlib import Path
from typing import Any

import httpx

from ..geo import BoundingBox, mercator_scale_at, to_mercator
from . import http

SERVICE = "https://elevation.nationalmap.gov/arcgis/rest/services/3DEPElevation/ImageServer"

# The service reports maxImageWidth/Height of 8000. Chunks are kept well under that: a
# smaller request is quicker to retry when the service is busy, and 2048 × 2048 float32 is
# a 16 MB response.
CHUNK_PIXELS = 2048

NO_DATA = -999999.0

TERMS = {
    "identifier": "usgs-3dep",
    "title": "USGS 3D Elevation Program (3DEP), dynamic elevation image service",
    "url": SERVICE,
    "licence": "Public domain (US Geological Survey)",
    "attribution": "Elevation data courtesy of the U.S. Geological Survey (3DEP)",
    "notes": (
        "Bare-earth elevation in metres. Multi-resolution: 1/3 arc-second (about 10 m) "
        "nationally, finer where lidar exists. Requested here at a fixed ground "
        "resolution so every park is measured on the same grid."
    ),
}


def plan_grid(box: BoundingBox, ground_resolution_m: float) -> dict[str, Any]:
    """The pixel grid a park's elevation will be fetched on.

    Pixel size is in Mercator metres but chosen from a *ground* resolution: Mercator
    stretches by ``1 / cos(latitude)``, so without the correction a park in Alaska would
    be sampled twice as finely as one in Utah and the packs would not be comparable.
    """
    _, centre_latitude = box.centre
    pixel_size = ground_resolution_m * mercator_scale_at(centre_latitude)
    min_x, min_y = to_mercator(box.west, box.south)
    max_x, max_y = to_mercator(box.east, box.north)
    columns = max(1, math.ceil((max_x - min_x) / pixel_size))
    rows = max(1, math.ceil((max_y - min_y) / pixel_size))
    return {
        "crs": "EPSG:3857",
        "origin_x": min_x,
        "origin_y": min_y + rows * pixel_size,  # top-left corner: y counts down
        "pixel_size": pixel_size,
        "columns": columns,
        "rows": rows,
        "ground_resolution_m": ground_resolution_m,
        "centre_latitude": centre_latitude,
        "no_data": NO_DATA,
    }


def download(
    session: httpx.Client,
    directory: Path,
    box: BoundingBox,
    ground_resolution_m: float,
    *,
    record: Any = None,
    chunk_pixels: int = CHUNK_PIXELS,
) -> dict[str, Any]:
    """Fetch the grid into ``directory`` and return the index that describes it."""
    grid = plan_grid(box, ground_resolution_m)
    pixel_size = grid["pixel_size"]
    chunks: list[dict[str, Any]] = []

    row_starts = list(range(0, grid["rows"], chunk_pixels))
    column_starts = list(range(0, grid["columns"], chunk_pixels))
    total = len(row_starts) * len(column_starts)
    done = 0

    for row_start in row_starts:
        row_end = min(row_start + chunk_pixels, grid["rows"])
        for column_start in column_starts:
            column_end = min(column_start + chunk_pixels, grid["columns"])
            width = column_end - column_start
            height = row_end - row_start
            chunk_min_x = grid["origin_x"] + column_start * pixel_size
            chunk_max_x = grid["origin_x"] + column_end * pixel_size
            chunk_max_y = grid["origin_y"] - row_start * pixel_size
            chunk_min_y = grid["origin_y"] - row_end * pixel_size
            parameters = {
                "bbox": f"{chunk_min_x},{chunk_min_y},{chunk_max_x},{chunk_max_y}",
                "bboxSR": "3857",
                "imageSR": "3857",
                "size": f"{width},{height}",
                "format": "tiff",
                "pixelType": "F32",
                "noData": str(NO_DATA),
                "interpolation": "RSP_BilinearInterpolation",
                "f": "image",
            }
            name = f"chunk-r{row_start:05d}-c{column_start:05d}.tif"
            response = http.get(
                session, f"{SERVICE}/exportImage", params=parameters, expect="image/tiff"
            )
            path = http.write_bytes(directory / name, response.content)
            done += 1
            print(
                f"    3DEP chunk {done}/{total}: {width}×{height} px, "
                f"{path.stat().st_size / 1e6:.1f} MB"
            )
            if record is not None:
                record.add_request(f"{SERVICE}/exportImage", parameters)
                record.add_file(path, root=directory.parent.parent)
            chunks.append(
                {
                    "file": name,
                    "column": column_start,
                    "row": row_start,
                    "columns": width,
                    "rows": height,
                }
            )

    index = {**grid, "chunks": chunks, "bounds": box.as_list()}
    (directory / "index.json").write_text(json.dumps(index, indent=2) + "\n")
    return index
