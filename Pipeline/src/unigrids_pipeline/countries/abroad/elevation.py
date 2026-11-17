"""Elevation abroad, from the Copernicus GLO-30 surface model.

At home every trail is measured on USGS 3DEP. Abroad there is no 3DEP, and Japan's and
Norway's own terrain models differ in resolution, licence and coverage (Svalbard has its
own). So one model measures everything abroad: Copernicus GLO-30, a 30 m model of the
whole globe, published on a public AWS bucket as one Cloud-Optimised GeoTIFF per 1° tile
(``docs/sources-japan-norway.md``, B7).

How the tiles are laid out, from the bucket's own readme:

* ``Copernicus_DSM_COG_10_N61_00_E008_00_DEM`` covers 61–62° N, 8–9° E: the name is the
  tile's south-west corner.
* Every tile is 3,600 rows of 1″. Columns widen towards the poles — 1″ below 50°, 1.5″ to
  60°, 2″ to 70°, 3″ to 80°, 5″ to 85° — so a tile is 3,600, 2,400, 1,800, 1,200 or 720
  columns wide.
* Pixel 0, 0 sits *on* the north-west corner (GeoTIFF ``PixelIsPoint``); the bucket
  removed the original files' shared south and east edges, so tiles do not overlap and a
  point on a tile's south edge is the next tile's first row.
* Ocean has no tiles, and "there one can assume height values equal to zero". A tile
  missing from the published list is therefore sea level, not a hole.
* The files are DEFLATE with the floating-point predictor (``PREDICTOR=3``), which
  ``tifffile`` cannot undo without ``imagecodecs``. The pipeline reads the file's layout
  with ``tifffile`` and decodes the blocks itself (TIFF Technical Note 3), so no new
  dependency is needed.

GLO-30 is a *surface* model: forest canopy and buildings are in its heights. A summit is
bare and reads true; a forest trail's profile rides a few metres high. It never overrides
an official summit height, only fills a figure no source gives, and says so
(:data:`NOTE`).
"""

from __future__ import annotations

import hashlib
import json
import math
import zlib
from collections import OrderedDict
from collections.abc import Iterable
from pathlib import Path
from typing import Any

import httpx
import numpy as np
import tifffile
from PIL import Image, ImageDraw

from ... import config, outline, rawstore
from ...geo import BoundingBox
from ...rawstore import FetchRecord, SourceTerms
from ...sources import http, threedep

BUCKET = "https://copernicus-dem-30m.s3.amazonaws.com"
SOURCE = "copernicus-dem"
TILE_LIST = "tileList.txt"

CREDIT = (
    "Copernicus GLO-30 (© DLR e.V. 2010–2014 and © Airbus Defence and Space GmbH "
    "2014–2018, provided under COPERNICUS by the European Union and ESA)"
)
"""The credit the app shows wherever a figure measured on GLO-30 appears."""

NOTE = "Measured by Unigrids from Copernicus GLO-30"
"""A park fact's ``elevationNote`` when the figure was measured here."""

LIABILITY = (
    "The organisations in charge of the Copernicus programme by law or by delegation do not "
    "incur any liability for any use of the Copernicus WorldDEM-30."
)
"""The notice the licence (Art. 6) obliges anyone distributing the data to carry."""

TERMS = SourceTerms(
    identifier="copernicus-dem-glo30",
    title="Copernicus DEM GLO-30 Public, Cloud-Optimised GeoTIFFs on AWS",
    url=f"{BUCKET}/readme.html",
    licence=(
        "Licence for the use of the Copernicus WorldDEM-30: free of charge, worldwide; "
        "reproduction, distribution, adaptation and combination allowed (Art. 3–5)"
    ),
    attribution=(
        "produced using Copernicus WorldDEM-30 © DLR e.V. 2010-2014 and © Airbus Defence "
        "and Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; "
        "all rights reserved"
    ),
    notes=(
        "A digital surface model: canopy and buildings are in the heights. One 1° tile per "
        "file, cached as published; ocean has no tile and is sea level. " + LIABILITY
    ),
)

ROW_STEP_DEGREES = 1 / 3600
"""Every GLO-30 tile's row spacing, whatever its latitude."""

NO_DATA_FLOOR = -1000.0
"""Below any land on Earth: anything lower is a fill value, not ground."""

SEA_LEVEL_BAND_M = 3
"""A lowest point this close to zero, or below it, is the sea (``park_extremes``)."""

GRID_NO_DATA = threedep.NO_DATA
"""What a pack's elevation grid writes where the model has nothing, so ``dem`` reads it
back as a hole exactly as it reads 3DEP's."""

CACHED_TILES = 6
"""Open tiles kept with their decoded blocks: a park rarely spans more, and each tile's
blocks can come to 64 MB."""


# MARK: - Tile names


def tile_name(latitude: int, longitude: int) -> str:
    """The bucket's name for the tile whose south-west corner is ``latitude, longitude``."""
    north = "N" if latitude >= 0 else "S"
    east = "E" if longitude >= 0 else "W"
    return f"Copernicus_DSM_COG_10_{north}{abs(latitude):02d}_00_{east}{abs(longitude):03d}_00_DEM"


def tile_url(name: str) -> str:
    return f"{BUCKET}/{name}/{name}.tif"


def column_step_degrees(latitude: int) -> float:
    """Column spacing of the tile whose south edge is ``latitude``, from the readme."""
    edge = min(abs(latitude), abs(latitude + 1))
    for limit, seconds in ((50, 1.0), (60, 1.5), (70, 2.0), (80, 3.0), (85, 5.0)):
        if edge < limit:
            return seconds / 3600
    return 10.0 / 3600


def tile_of(longitude: float, latitude: float) -> tuple[int, int]:
    """The tile a point is interpolated in: its row above the point is in this tile.

    Rows run from the tile's north edge down to a pixel short of its south edge, so a
    point exactly on an integer latitude belongs to the tile below it.
    """
    return math.ceil(latitude) - 1, math.floor(longitude)


def tiles_for_box(south: float, west: float, north: float, east: float) -> list[tuple[int, int]]:
    """Every tile bilinear sampling inside the box can touch, south-west corners."""
    margin = 10 / 3600  # a pixel at the widest spacing, for the neighbour row or column
    rows = range(math.ceil(south - margin) - 1, math.ceil(north) - 1 + 1)
    columns = range(math.floor(west), math.floor(east + margin) + 1)
    return [(latitude, longitude) for latitude in rows for longitude in columns]


# MARK: - Reading a tile


class GeoTiffError(ValueError):
    """A GeoTIFF this reader does not understand."""


def undo_floating_point_predictor(data: bytes, rows: int, columns: int) -> np.ndarray:
    """Float32 values from a block written with TIFF's floating-point predictor.

    TIFF Technical Note 3: each row's values are split into byte planes, most significant
    byte first, and the row of bytes is then stored as differences. Undoing it is a running
    sum along the row (modulo 256), then putting each value's four bytes back together in
    big-endian order — whatever the file's own byte order.
    """
    planes = np.frombuffer(data, dtype=np.uint8)[: rows * columns * 4].reshape(rows, 4 * columns)
    summed = np.cumsum(planes, axis=1, dtype=np.uint8)
    values = summed.reshape(rows, 4, columns).transpose(0, 2, 1).copy()
    return values.view(">f4").reshape(rows, columns).astype(np.float32)


class DemTile:
    """One GeoTIFF tile: its layout read once, its blocks decoded as they are asked for.

    ``origin_longitude``/``origin_latitude`` is the centre of pixel ``(0, 0)``; rows go
    south by ``step_latitude`` and columns east by ``step_longitude``.
    """

    def __init__(self, path: Path) -> None:
        self.path = path
        with tifffile.TiffFile(path) as tiff:
            page = tiff.pages[0]
            tags = page.tags
            self.rows = int(page.imagelength)
            self.columns = int(page.imagewidth)
            self.block_rows = int(page.tilelength or page.rowsperstrip or self.rows)
            self.block_columns = int(page.tilewidth or self.columns)
            self.offsets = tuple(int(value) for value in page.dataoffsets)
            self.counts = tuple(int(value) for value in page.databytecounts)
            self.compression = int(page.compression)
            self.predictor = int(page.predictor)
            self.byteorder = tiff.byteorder
            if page.dtype != np.float32 and page.dtype != np.int16:
                raise GeoTiffError(f"{path.name}: samples are {page.dtype}, not float32")
            self.dtype = np.dtype(page.dtype).newbyteorder(self.byteorder)
            scale = tags.get(33550)
            tiepoint = tags.get(33922)
            if scale is None or tiepoint is None:
                raise GeoTiffError(f"{path.name}: no GeoTIFF pixel scale or tie point")
            step_x, step_y = float(scale.value[0]), float(scale.value[1])
            pixel_i, pixel_j, _, x, y, _ = (float(value) for value in tiepoint.value[:6])
            keys = tags.get(34735)
            is_point = _raster_type(keys.value if keys else ()) == 2
        half_x, half_y = (0.0, 0.0) if is_point else (step_x / 2, step_y / 2)
        self.step_longitude = step_x
        self.step_latitude = step_y
        self.origin_longitude = x - pixel_i * step_x + half_x
        self.origin_latitude = y + pixel_j * step_y - half_y
        self.blocks_across = math.ceil(self.columns / self.block_columns)
        self._blocks: dict[int, np.ndarray] = {}

    def block(self, index: int) -> np.ndarray:
        """One internal block, decoded, as float32 with holes as NaN."""
        if (cached := self._blocks.get(index)) is not None:
            return cached
        with self.path.open("rb") as handle:
            handle.seek(self.offsets[index])
            payload = handle.read(self.counts[index])
        if self.compression in (8, 32946):
            payload = zlib.decompress(payload)
        elif self.compression != 1:
            raise GeoTiffError(f"{self.path.name}: compression {self.compression} not read")
        if self.predictor == 3:
            values = undo_floating_point_predictor(payload, self.block_rows, self.block_columns)
        elif self.predictor == 1:
            count = self.block_rows * self.block_columns
            values = np.frombuffer(payload, dtype=self.dtype)[:count]
            values = values.reshape(self.block_rows, self.block_columns).astype(np.float32)
        else:
            raise GeoTiffError(f"{self.path.name}: predictor {self.predictor} not read")
        values = np.where(values > NO_DATA_FLOOR, values, np.nan).astype(np.float32)
        self._blocks[index] = values
        return values

    def values(self, rows: np.ndarray, columns: np.ndarray) -> np.ndarray:
        """Pixels at integer ``rows`` and ``columns`` (in range), as float64."""
        rows = np.asarray(rows, dtype=np.int64)
        columns = np.asarray(columns, dtype=np.int64)
        result = np.empty(rows.shape, dtype=np.float64)
        indices = (rows // self.block_rows) * self.blocks_across + columns // self.block_columns
        for index in np.unique(indices):
            chosen = indices == index
            block = self.block(int(index))
            result[chosen] = block[
                rows[chosen] % self.block_rows, columns[chosen] % self.block_columns
            ]
        return result

    def pixel(self, row: int, column: int) -> float:
        index = (row // self.block_rows) * self.blocks_across + column // self.block_columns
        return float(self.block(index)[row % self.block_rows, column % self.block_columns])

    def read(self) -> np.ndarray:
        """The whole tile, float32, holes as NaN."""
        whole = np.full(
            (
                math.ceil(self.rows / self.block_rows) * self.block_rows,
                self.blocks_across * self.block_columns,
            ),
            np.nan,
            dtype=np.float32,
        )
        for index in range(len(self.offsets)):
            row, column = divmod(index, self.blocks_across)
            whole[
                row * self.block_rows : (row + 1) * self.block_rows,
                column * self.block_columns : (column + 1) * self.block_columns,
            ] = self.block(index)
        return whole[: self.rows, : self.columns]


class SeaTile:
    """A tile the bucket does not publish because it is all ocean: sea level throughout."""

    def __init__(self, latitude: int, longitude: int) -> None:
        self.rows = 3600
        self.columns = round(1 / column_step_degrees(latitude))
        self.step_latitude = ROW_STEP_DEGREES
        self.step_longitude = column_step_degrees(latitude)
        self.origin_latitude = latitude + 1.0
        self.origin_longitude = float(longitude)

    def values(self, rows: np.ndarray, columns: np.ndarray) -> np.ndarray:
        return np.zeros(np.shape(rows), dtype=np.float64)

    def pixel(self, row: int, column: int) -> float:
        return 0.0

    def read(self) -> np.ndarray:
        return np.zeros((self.rows, self.columns), dtype=np.float32)


Tile = DemTile | SeaTile


def _raster_type(keys: Iterable[int]) -> int:
    """``GTRasterTypeGeoKey`` (1025) from a GeoKeyDirectory: 1 area, 2 point."""
    values = list(keys)
    for start in range(4, len(values) - 3, 4):
        if values[start] == 1025 and values[start + 1] == 0:
            return int(values[start + 3])
    return 1


# MARK: - The model


class CopernicusDEM:
    """GLO-30 as one surface: tiles found in the raw store, fetched when missing and
    ``online``, and sampled bilinearly across tile edges.

    ``directory`` pins the cache to one folder (tests); by default every dated
    ``raw/<date>/copernicus-dem/`` is searched, newest first, since the ground does not
    move between fetches, and a new tile lands in today's.
    """

    def __init__(self, *, online: bool = True, directory: Path | None = None) -> None:
        self.online = online
        self.directory = directory
        self._tiles: OrderedDict[tuple[int, int], Tile | None] = OrderedDict()
        self._published: set[str] | None = None
        self._session: httpx.Client | None = None
        self.downloaded = 0

    # MARK: Sampling

    def sample(self, longitude: float, latitude: float) -> float | None:
        """Bilinear elevation in metres, or ``None`` where the model has nothing — the
        shape ``measure.ElevationSampler`` asks for."""
        tile_lat, tile_lon = tile_of(longitude, latitude)
        tile = self.tile(tile_lat, tile_lon)
        if tile is None:
            return None
        row = (tile.origin_latitude - latitude) / tile.step_latitude
        column = (longitude - tile.origin_longitude) / tile.step_longitude
        row_0, column_0 = math.floor(row), math.floor(column)
        if 0 <= row_0 < tile.rows - 1 and 0 <= column_0 < tile.columns - 1:
            fraction_y, fraction_x = row - row_0, column - column_0
            top_left = tile.pixel(row_0, column_0)
            top_right = tile.pixel(row_0, column_0 + 1)
            bottom_left = tile.pixel(row_0 + 1, column_0)
            bottom_right = tile.pixel(row_0 + 1, column_0 + 1)
            top = top_left + (top_right - top_left) * fraction_x
            bottom = bottom_left + (bottom_right - bottom_left) * fraction_x
            value = top + (bottom - top) * fraction_y
        else:
            value = float(self.sample_many(np.array([longitude]), np.array([latitude]))[0])
        return None if math.isnan(value) else value

    def sample_many(self, longitudes: np.ndarray, latitudes: np.ndarray) -> np.ndarray:
        """Bilinear elevation for many points at once; ``NaN`` where the model has none."""
        longitudes = np.asarray(longitudes, dtype=np.float64)
        latitudes = np.asarray(latitudes, dtype=np.float64)
        shape = longitudes.shape
        longitudes, latitudes = longitudes.ravel(), latitudes.ravel()
        result = np.full(longitudes.shape, np.nan)
        tile_lats = np.ceil(latitudes).astype(np.int64) - 1
        tile_lons = np.floor(longitudes).astype(np.int64)
        keys = tile_lats * 1000 + tile_lons
        for key in np.unique(keys):
            chosen = np.nonzero(keys == key)[0]
            tile_lat, tile_lon = int(tile_lats[chosen[0]]), int(tile_lons[chosen[0]])
            tile = self.tile(tile_lat, tile_lon)
            if tile is None:
                continue
            row = (tile.origin_latitude - latitudes[chosen]) / tile.step_latitude
            row_0 = np.clip(np.floor(row), 0, tile.rows - 1).astype(np.int64)
            fraction_y = np.clip(row - row_0, 0.0, 1.0)
            lons = longitudes[chosen]
            upper = self._row_values(tile_lat, tile_lon, tile, row_0, lons)
            lower = np.full(upper.shape, np.nan)
            inside = row_0 + 1 < tile.rows
            lower[inside] = self._row_values(
                tile_lat, tile_lon, tile, row_0[inside] + 1, lons[inside]
            )
            if not inside.all():
                # The row below is the next tile south's first row.
                south = self.tile(tile_lat - 1, tile_lon)
                if south is not None:
                    edge = ~inside
                    lower[edge] = self._row_values(
                        tile_lat - 1, tile_lon, south, np.zeros(edge.sum(), np.int64), lons[edge]
                    )
            result[chosen] = upper + (lower - upper) * fraction_y
        return result.reshape(shape)

    def _row_values(
        self, tile_lat: int, tile_lon: int, tile: Tile, rows: np.ndarray, longitudes: np.ndarray
    ) -> np.ndarray:
        """One row's values interpolated along it at each longitude."""
        column = (longitudes - tile.origin_longitude) / tile.step_longitude
        column_0 = np.clip(np.floor(column), 0, tile.columns - 1).astype(np.int64)
        fraction_x = np.clip(column - column_0, 0.0, 1.0)
        left = tile.values(rows, column_0)
        right = np.full(left.shape, np.nan)
        inside = column_0 + 1 < tile.columns
        right[inside] = tile.values(rows[inside], column_0[inside] + 1)
        if not inside.all():
            # The column to the east is the next tile east's first, on the same row.
            east = self.tile(tile_lat, tile_lon + 1)
            if east is not None:
                edge = ~inside
                right[edge] = east.values(rows[edge], np.zeros(edge.sum(), np.int64))
        return left + (right - left) * fraction_x

    # MARK: Tiles

    def tile(self, latitude: int, longitude: int) -> Tile | None:
        """A tile by its south-west corner: read from the cache, fetched if allowed, sea
        if the bucket publishes none there, ``None`` if it cannot be had."""
        key = (latitude, longitude)
        if key in self._tiles:
            self._tiles.move_to_end(key)
            return self._tiles[key]
        found = self._open(latitude, longitude)
        self._tiles[key] = found
        while len(self._tiles) > CACHED_TILES:
            self._tiles.popitem(last=False)
        return found

    def _open(self, latitude: int, longitude: int) -> Tile | None:
        name = tile_name(latitude, longitude)
        if (path := self._cached(f"{name}.tif")) is not None:
            return DemTile(path)
        published = self.published()
        if published is not None and name not in published:
            return SeaTile(latitude, longitude)
        if not self.online or published is None:
            return None
        try:
            return DemTile(self._download(name))
        except http.FetchError as error:
            print(f"    {SOURCE}: {name} could not be fetched ({error})")
            return None

    def published(self) -> set[str] | None:
        """The bucket's list of tiles that exist: anything else is ocean."""
        if self._published is None:
            path = self._cached(TILE_LIST)
            if path is None and self.online:
                try:
                    path = self._fetch(f"{BUCKET}/{TILE_LIST}", TILE_LIST, expect="text")
                except http.FetchError as error:
                    print(f"    {SOURCE}: the tile list could not be fetched ({error})")
            if path is not None:
                self._published = set(path.read_text().split())
        return self._published

    def _directories(self) -> list[Path]:
        if self.directory is not None:
            return [self.directory]
        return [config.RAW_DIR / version / SOURCE for version in rawstore.versions(SOURCE)]

    def _cached(self, filename: str) -> Path | None:
        for directory in self._directories():
            if (path := directory / filename).exists():
                return path
        return None

    def _download(self, name: str) -> Path:
        path = self._fetch(tile_url(name), f"{name}.tif", expect="image/tiff")
        self.downloaded += 1
        print(f"    {SOURCE}: {name} ({path.stat().st_size / 1e6:.1f} MB)", flush=True)
        return path

    def _fetch(self, url: str, filename: str, *, expect: str) -> Path:
        directory = self.directory or rawstore.version_directory(SOURCE)
        directory.mkdir(parents=True, exist_ok=True)
        if self._session is None:
            self._session = http.client(http.Politeness(timeout_seconds=300.0))
        response = http.get(self._session, url, expect=expect)
        partial = directory / f"{filename}.part"
        partial.write_bytes(response.content)
        path = directory / filename
        partial.replace(path)
        # Read back and added to on every download, so two builds filling the same day's
        # folder (Japan's and Norway's) keep each other's entries.
        record = FetchRecord(source=TERMS, fetched_at=rawstore.utc_now())
        existing = directory / "source.json"
        if existing.exists():
            payload = json.loads(existing.read_text())
            record.requests = list(payload.get("requests") or [])
            record.files = [
                entry for entry in payload.get("files") or [] if entry["path"] != filename
            ]
        record.add_request(url)
        record.add_file(path, root=directory)
        record.write(directory)
        return path

    def close(self) -> None:
        if self._session is not None:
            self._session.close()
            self._session = None

    def fetch_box(self, south: float, west: float, north: float, east: float) -> int:
        """Make sure every tile a box needs is in the cache. Returns how many were missing."""
        before = self.downloaded
        for latitude, longitude in tiles_for_box(south, west, north, east):
            self.tile(latitude, longitude)
        return self.downloaded - before


def sampler(*, online: bool = True) -> CopernicusDEM:
    """The model, ready to sample: ``sampler().sample`` is a ``measure.ElevationSampler``."""
    return CopernicusDEM(online=online)


# MARK: - Park extremes


def park_extremes(
    polygons: list[outline.Polygon],
    *,
    dem: CopernicusDEM | None = None,
    online: bool = True,
) -> tuple[int, int] | None:
    """A park's lowest and highest ground, in whole metres, from every GLO-30 pixel whose
    centre lies inside its outline.

    The outline is rasterised onto each tile's own pixel grid, so nothing is resampled:
    the figures are elevations of real pixels. A lowest point within
    :data:`SEA_LEVEL_BAND_M` of zero is the sea and given as 0, as at home — and so is one
    below zero: no park in Japan or Norway has dry land below the sea, and GLO-30's sea
    surface inside a coastal tile reads a few metres either side of it (Sør-Spitsbergen's
    comes to −16 m). ``None`` when a tile the outline needs cannot be read, rather than
    extremes over part of the park.
    """
    box = outline.bbox(polygons)
    if box is None:
        return None
    model = dem or CopernicusDEM(online=online)
    south, west, north, east = box
    lowest, highest = math.inf, -math.inf
    for latitude in range(math.ceil(south) - 1, math.ceil(north)):
        for longitude in range(math.floor(west), math.floor(east) + 1):
            # The bucket's layout says where a tile's pixels are before it is read, so a
            # tile in the outline's box that the outline does not reach is never fetched.
            layout = SeaTile(latitude, longitude)
            mask = _mask(polygons, layout)
            if not mask.any():
                continue
            tile = model.tile(latitude, longitude)
            if tile is None:
                return None
            if not _same_grid(tile, layout):
                mask = _mask(polygons, tile)
            for low, high in _masked_extremes(tile, mask):
                lowest, highest = min(lowest, low), max(highest, high)
    if not math.isfinite(lowest) or not math.isfinite(highest):
        return None
    low = round(lowest)
    if low <= SEA_LEVEL_BAND_M:
        low = 0
    return low, round(highest)


def _same_grid(tile: Tile, other: Tile) -> bool:
    return (
        (tile.rows, tile.columns) == (other.rows, other.columns)
        and math.isclose(tile.origin_latitude, other.origin_latitude, abs_tol=1e-9)
        and math.isclose(tile.origin_longitude, other.origin_longitude, abs_tol=1e-9)
        and math.isclose(tile.step_longitude, other.step_longitude, rel_tol=1e-9)
    )


def _mask(polygons: list[outline.Polygon], tile: Tile) -> np.ndarray:
    """Which of a tile's pixels have their centre inside the outline. Each polygon's
    exterior is filled and its holes cut before the next polygon is drawn."""
    image = Image.new("1", (tile.columns, tile.rows), 0)
    draw = ImageDraw.Draw(image)

    def pixels(ring: outline.Ring) -> list[tuple[float, float]]:
        return [
            (
                (longitude - tile.origin_longitude) / tile.step_longitude + 0.5,
                (tile.origin_latitude - latitude) / tile.step_latitude + 0.5,
            )
            for longitude, latitude in ring
        ]

    for polygon in polygons:
        for index, ring in enumerate(polygon):
            if len(ring) >= 3:
                draw.polygon(pixels(ring), fill=0 if index else 1)
    return np.array(image, dtype=bool)


def _masked_extremes(tile: Tile, mask: np.ndarray) -> Iterable[tuple[float, float]]:
    """Lowest and highest masked pixel, block by block, so a tile is never decoded whole
    for a park that touches a corner of it."""
    if isinstance(tile, SeaTile):
        yield 0.0, 0.0
        return
    for index in range(len(tile.offsets)):
        block_row, block_column = divmod(index, tile.blocks_across)
        rows = slice(block_row * tile.block_rows, (block_row + 1) * tile.block_rows)
        columns = slice(block_column * tile.block_columns, (block_column + 1) * tile.block_columns)
        part = mask[rows, columns]
        if not part.any():
            continue
        block = tile.block(index)[: part.shape[0], : part.shape[1]]
        values = block[part]
        values = values[np.isfinite(values)]
        if values.size:
            yield float(values.min()), float(values.max())


def attach_extremes(
    places: list[dict[str, Any]],
    outlines: dict[str, list[outline.Polygon]],
    *,
    online: bool = True,
    dem: CopernicusDEM | None = None,
    cache: ExtremesCache | None = None,
) -> int:
    """Fill each national park's missing ``lowestElevationMetres`` and
    ``highestElevationMetres`` from its outline, with :data:`NOTE`. A figure a guide
    already gives is left alone: an official height beats a surface model's.

    Every measurement is kept in ``cache`` (by default the raw store's, when no ``dem`` is
    handed in), and a park whose outline has not changed since is read from it without
    opening a tile. So the tiles — many gigabytes for the Arctic parks — can be deleted
    after a build, and a later build without them, offline, still carries every range.
    Where the tiles are gone and the outline has changed, the last measurement is used and
    said to be used; only a park never measured goes without, and is named.
    """
    model = dem or CopernicusDEM(online=online)
    if cache is None and dem is None:
        cache = ExtremesCache()
    filled = from_cache = 0
    unmeasured: list[str] = []
    for place in places:
        if place.get("kind") != "nationalPark":
            continue
        facts = place.setdefault("facts", {})
        if "lowestElevationMetres" in facts and "highestElevationMetres" in facts:
            continue
        polygons = outlines.get(place["id"])
        if not polygons:
            continue
        fingerprint = outline_fingerprint(polygons)
        extremes = cache.get(place["id"], fingerprint) if cache else None
        if extremes is not None:
            from_cache += 1
        else:
            extremes = park_extremes(polygons, dem=model)
            if extremes is not None and cache is not None:
                cache.put(place["id"], fingerprint, extremes)
        if extremes is None and cache is not None:
            extremes = cache.get(place["id"])
            if extremes is not None:
                from_cache += 1
                print(f"    elevation: {place['id']} from its last measurement (tiles "
                      "missing, outline changed since)")
        if extremes is None:
            unmeasured.append(place["id"])
            continue
        facts.setdefault("lowestElevationMetres", extremes[0])
        facts.setdefault("highestElevationMetres", extremes[1])
        facts["elevationNote"] = NOTE
        filled += 1
    if cache is not None:
        cache.save()
    print(f"    elevation: {filled} parks' ranges measured on Copernicus GLO-30 "
          f"({from_cache} read from the measurements kept in the raw store)")
    if unmeasured:
        print(f"    elevation: NOT MEASURED, tiles missing and never measured before "
              f"({len(unmeasured)}): {', '.join(unmeasured)}")
    return filled


# MARK: - Measurements kept

EXTREMES_SOURCE = "elevation-extremes"
EXTREMES_FILE = "extremes.json"

EXTREMES_TERMS = SourceTerms(
    identifier="copernicus-dem-glo30-extremes",
    title="Each national park's lowest and highest ground, measured on Copernicus GLO-30",
    url=f"{BUCKET}/readme.html",
    licence=TERMS.licence,
    attribution=TERMS.attribution,
    notes=(
        "Unigrids' own measurements (park_extremes), kept so the tiles they were read from "
        "can be deleted. Each entry carries the fingerprint of the outline it was measured "
        "over; a changed outline is measured again when the tiles are at hand. " + LIABILITY
    ),
)


def outline_fingerprint(polygons: list[outline.Polygon]) -> str:
    """A short digest of an outline's coordinates, to 1e-6°: the same raw outline gives the
    same fingerprint every run, and a redrawn one a different one."""
    digest = hashlib.sha1()
    for polygon in polygons:
        for ring in polygon:
            for longitude, latitude in ring:
                digest.update(f"{longitude:.6f},{latitude:.6f};".encode())
            digest.update(b"|")
        digest.update(b"#")
    return digest.hexdigest()[:16]


class ExtremesCache:
    """Park ID → its measured lowest and highest ground and the outline it was measured
    over, read from the newest ``raw/<date>/elevation-extremes/extremes.json`` and written,
    with everything read, to today's. ``directory`` pins it to one folder (tests)."""

    def __init__(self, directory: Path | None = None) -> None:
        self.directory = directory
        source = directory if directory is not None else rawstore.latest(
            EXTREMES_SOURCE, EXTREMES_FILE
        )
        path = source / EXTREMES_FILE if source is not None else None
        self.entries: dict[str, dict[str, Any]] = (
            json.loads(path.read_text()) if path is not None and path.exists() else {}
        )
        self._changed = False
        self._mine: dict[str, dict[str, Any]] = {}

    def get(self, place_id: str, fingerprint: str | None = None) -> tuple[int, int] | None:
        """The kept measurement, if the outline matches ``fingerprint`` (or any, if None)."""
        entry = self.entries.get(place_id)
        if not entry or (fingerprint is not None and entry.get("outline") != fingerprint):
            return None
        return int(entry["lowestMetres"]), int(entry["highestMetres"])

    def put(self, place_id: str, fingerprint: str, extremes: tuple[int, int]) -> None:
        entry = {
            "lowestMetres": extremes[0],
            "highestMetres": extremes[1],
            "outline": fingerprint,
        }
        if {k: v for k, v in (self.entries.get(place_id) or {}).items() if k in entry} != entry:
            self.entries[place_id] = {**entry, "measuredAt": rawstore.utc_now()}
            self._mine[place_id] = self.entries[place_id]
            self._changed = True

    def save(self) -> Path | None:
        """Write the measurements if any are new, with ``source.json`` beside them."""
        if not self._changed:
            return None
        directory = self.directory or rawstore.version_directory(EXTREMES_SOURCE)
        directory.mkdir(parents=True, exist_ok=True)
        path = directory / EXTREMES_FILE
        # Another country's build may have saved since this one read: keep its parks.
        if path.exists():
            on_disk = json.loads(path.read_text())
            self.entries = {**on_disk, **self._mine, **{
                key: value for key, value in self.entries.items() if key not in on_disk
            }}
        path.write_text(json.dumps(dict(sorted(self.entries.items())), indent=1) + "\n")
        record = FetchRecord(source=EXTREMES_TERMS, fetched_at=rawstore.utc_now())
        record.add_file(path, root=directory)
        record.write(directory)
        self._changed = False
        return path


# MARK: - A pack's grid


def write_grid(
    directory: Path,
    box: BoundingBox,
    *,
    ground_resolution_m: float = 30.0,
    dem: CopernicusDEM | None = None,
    online: bool = True,
    chunk_pixels: int = threedep.CHUNK_PIXELS,
) -> dict[str, Any]:
    """Resample GLO-30 onto a pack's Web Mercator grid, in the layout ``dem.ElevationGrid``
    reads 3DEP's: ``index.json`` and float32 chunks. Bilinear, at the model's own 30 m —
    finer would only interpolate, and the renderer shades at the grid's resolution."""
    model = dem or CopernicusDEM(online=online)
    directory.mkdir(parents=True, exist_ok=True)
    grid = threedep.plan_grid(box, ground_resolution_m)
    pixel = grid["pixel_size"]
    chunks: list[dict[str, Any]] = []
    for row_start in range(0, grid["rows"], chunk_pixels):
        row_end = min(row_start + chunk_pixels, grid["rows"])
        for column_start in range(0, grid["columns"], chunk_pixels):
            column_end = min(column_start + chunk_pixels, grid["columns"])
            x = grid["origin_x"] + (np.arange(column_start, column_end) + 0.5) * pixel
            y = grid["origin_y"] - (np.arange(row_start, row_end) + 0.5) * pixel
            grid_x, grid_y = np.meshgrid(x, y)
            longitudes = np.degrees(grid_x / 6378137.0)
            latitudes = np.degrees(2 * np.arctan(np.exp(grid_y / 6378137.0)) - np.pi / 2)
            values = model.sample_many(longitudes, latitudes).astype(np.float32)
            values[~np.isfinite(values)] = GRID_NO_DATA
            name = f"chunk-r{row_start:05d}-c{column_start:05d}.tif"
            tifffile.imwrite(directory / name, values, compression="zlib")
            chunks.append({
                "file": name,
                "column": column_start,
                "row": row_start,
                "columns": column_end - column_start,
                "rows": row_end - row_start,
            })
    index = {
        **grid,
        "chunks": chunks,
        "bounds": box.as_list(),
        "source": "Copernicus GLO-30, resampled bilinearly",
    }
    (directory / "index.json").write_text(json.dumps(index, indent=2) + "\n")
    return index
