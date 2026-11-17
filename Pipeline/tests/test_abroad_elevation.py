"""Copernicus GLO-30 abroad: naming tiles, reading them, sampling across their edges, and a
park's lowest and highest ground.

The fixtures are tiny synthetic GeoTIFFs laid out as the bucket lays its tiles out — the
north-west pixel sitting on the corner (``PixelIsPoint``), no shared edges — over a plane
whose height is a linear function of position. Bilinear interpolation of a plane is exact,
so any error in which pixel or which tile a point reads shows up as a wrong number.
"""

from __future__ import annotations

import math
from pathlib import Path

import numpy as np
import pytest
import tifffile

from unigrids_pipeline.countries.abroad import elevation

SIZE = 36
"""Pixels a side in a synthetic tile: 100″ spacing, so a tile is still 1°."""


def plane(longitude: float | np.ndarray, latitude: float | np.ndarray) -> float | np.ndarray:
    return 1000.0 * (latitude - 60.0) + 100.0 * (longitude - 8.0) + 50.0


def write_tile(
    directory: Path, latitude: int, longitude: int, *, tile: int = 16, fill: float | None = None
) -> Path:
    """A ``SIZE`` × ``SIZE`` tile over :func:`plane`, tiled and DEFLATE-compressed; its
    north-west quarter set to ``fill`` when one is given."""
    step = 1.0 / SIZE
    rows = latitude + 1 - np.arange(SIZE) * step
    columns = longitude + np.arange(SIZE) * step
    grid_lon, grid_lat = np.meshgrid(columns, rows)
    values = plane(grid_lon, grid_lat).astype(np.float32)
    if fill is not None:
        values[: SIZE // 2, : SIZE // 2] = fill
    path = directory / f"{elevation.tile_name(latitude, longitude)}.tif"
    tifffile.imwrite(
        path,
        values,
        tile=(tile, tile),
        compression="zlib",
        extratags=[
            (33550, "d", 3, (step, step, 0.0), True),
            (33922, "d", 6, (0.0, 0.0, 0.0, float(longitude), float(latitude + 1), 0.0), True),
            # GTModelType geographic, GTRasterType PixelIsPoint, WGS 84.
            (34735, "H", 16, (1, 1, 0, 3, 1024, 0, 1, 2, 1025, 0, 1, 2, 2048, 0, 1, 4326), True),
        ],
    )
    return path


@pytest.fixture
def dem(tmp_path: Path) -> elevation.CopernicusDEM:
    """Four land tiles, 60–62° N and 8–10° E, and a tile list naming only them."""
    names = []
    for latitude in (60, 61):
        for longitude in (8, 9):
            write_tile(tmp_path, latitude, longitude)
            names.append(elevation.tile_name(latitude, longitude))
    (tmp_path / elevation.TILE_LIST).write_text("\n".join(names) + "\n")
    return elevation.CopernicusDEM(online=False, directory=tmp_path)


# --- naming -----------------------------------------------------------------------------


def test_a_tile_is_named_by_its_south_west_corner():
    assert elevation.tile_name(61, 8) == "Copernicus_DSM_COG_10_N61_00_E008_00_DEM"
    assert elevation.tile_name(35, 138) == "Copernicus_DSM_COG_10_N35_00_E138_00_DEM"
    assert elevation.tile_name(-5, -70) == "Copernicus_DSM_COG_10_S05_00_W070_00_DEM"
    assert elevation.tile_url("Copernicus_DSM_COG_10_N61_00_E008_00_DEM") == (
        "https://copernicus-dem-30m.s3.amazonaws.com/Copernicus_DSM_COG_10_N61_00_E008_00_DEM/"
        "Copernicus_DSM_COG_10_N61_00_E008_00_DEM.tif"
    )


def test_a_point_on_an_integer_latitude_is_the_first_row_of_the_tile_below():
    assert elevation.tile_of(8.5, 61.5) == (61, 8)
    assert elevation.tile_of(8.5, 61.0) == (60, 8)
    assert elevation.tile_of(-0.5, 35.2) == (35, -1)


def test_columns_widen_towards_the_pole_as_the_readme_says():
    assert elevation.column_step_degrees(35) * 3600 == pytest.approx(1.0)
    assert elevation.column_step_degrees(55) * 3600 == pytest.approx(1.5)
    assert elevation.column_step_degrees(61) * 3600 == pytest.approx(2.0)
    assert elevation.column_step_degrees(78) * 3600 == pytest.approx(3.0)
    assert elevation.column_step_degrees(80) * 3600 == pytest.approx(5.0)


def test_a_box_asks_for_the_neighbours_its_edge_samples_need():
    tiles = elevation.tiles_for_box(61.0001, 8.2, 61.9, 8.99999)
    # The row south of the box's edge is the next tile south's first row, and the column
    # east of 8.99999 is the next tile east's first column.
    assert set(tiles) == {(60, 8), (60, 9), (61, 8), (61, 9)}


# --- reading ----------------------------------------------------------------------------


def test_the_floating_point_predictor_is_undone_to_the_bit():
    values = (np.arange(4 * 6, dtype=np.float32).reshape(4, 6) - 7.25) * 123.456
    planes = values.astype(">f4").view(np.uint8).reshape(4, 6, 4).transpose(0, 2, 1).reshape(4, 24)
    encoded = np.diff(planes.astype(np.int16), axis=1, prepend=0).astype(np.uint8)
    decoded = elevation.undo_floating_point_predictor(encoded.tobytes(), 4, 6)
    assert np.array_equal(decoded, values)


def test_a_tile_reads_its_georeferencing_and_its_padded_blocks(tmp_path: Path):
    path = write_tile(tmp_path, 61, 8)
    tile = elevation.DemTile(path)
    assert (tile.rows, tile.columns) == (SIZE, SIZE)
    assert tile.origin_longitude == pytest.approx(8.0)
    assert tile.origin_latitude == pytest.approx(62.0)
    whole = tile.read()
    assert whole.shape == (SIZE, SIZE)
    assert whole[0, 0] == pytest.approx(plane(8.0, 62.0))
    assert whole[-1, -1] == pytest.approx(plane(8.0 + 35 / SIZE, 61.0 + 1 / SIZE), abs=1e-3)


def test_a_tile_is_read_once_for_all_its_blocks(tmp_path: Path):
    tile = elevation.DemTile(write_tile(tmp_path, 61, 8))
    first = tile.block(0)
    assert tile.block(0) is first


# --- sampling ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("longitude", "latitude"),
    [
        (8.5123, 61.4321),  # inside a tile
        (8.7, 61.0 + 0.5 / SIZE),  # between a tile's last row and the next tile's first
        (8.0 + 35.5 / SIZE, 61.3),  # between a tile's last column and the next tile's first
        (8.0 + 35.5 / SIZE, 61.0 + 0.5 / SIZE),  # the corner where four tiles meet
        (9.25, 61.0),  # exactly on an integer latitude
    ],
)
def test_bilinear_sampling_is_exact_on_a_plane_across_tile_edges(dem, longitude, latitude):
    assert dem.sample(longitude, latitude) == pytest.approx(plane(longitude, latitude), abs=1e-3)


def test_sampling_many_points_agrees_with_sampling_one(dem):
    longitudes = np.array([8.1, 8.5, 8.0 + 35.5 / SIZE, 9.9])
    latitudes = np.array([60.2, 61.0 + 0.5 / SIZE, 61.7, 61.99])
    many = dem.sample_many(longitudes, latitudes)
    one = [dem.sample(lon, lat) for lon, lat in zip(longitudes, latitudes, strict=True)]
    assert many == pytest.approx(one)


def test_a_tile_the_bucket_does_not_publish_is_sea_level(dem):
    assert dem.sample(30.5, 61.5) == 0.0


def test_without_a_tile_list_or_the_network_nothing_is_guessed(tmp_path: Path):
    model = elevation.CopernicusDEM(online=False, directory=tmp_path)
    assert model.sample(8.5, 61.5) is None


def test_a_hole_in_the_model_is_none_not_a_number(tmp_path: Path):
    write_tile(tmp_path, 61, 8, fill=-32767.0)
    (tmp_path / elevation.TILE_LIST).write_text(elevation.tile_name(61, 8) + "\n")
    model = elevation.CopernicusDEM(online=False, directory=tmp_path)
    assert model.sample(8.05, 61.95) is None
    assert model.sample(8.9, 61.1) == pytest.approx(plane(8.9, 61.1), abs=1e-3)


# --- park extremes ----------------------------------------------------------------------


def square(west: float, south: float, east: float, north: float) -> list[tuple[float, float]]:
    return [(west, south), (east, south), (east, north), (west, north)]


def test_extremes_are_the_pixels_inside_the_outline(dem):
    polygons = [[square(8.2, 61.2, 8.6, 61.6)]]
    low, high = elevation.park_extremes(polygons, dem=dem)
    # The plane rises north and east; the pixel centres nearest the corners are inside.
    assert low == pytest.approx(plane(8.2, 61.2), abs=40)
    assert high == pytest.approx(plane(8.6, 61.6), abs=40)
    assert low < high


def test_extremes_follow_an_outline_across_tiles_and_leave_out_its_holes(dem):
    outer = square(8.8, 60.8, 9.2, 61.2)
    hole = square(9.1, 61.1, 9.2, 61.2)
    with_hole = elevation.park_extremes([[outer, hole]], dem=dem)
    without = elevation.park_extremes([[outer]], dem=dem)
    assert with_hole is not None and without is not None
    assert with_hole[0] == without[0]
    assert with_hole[1] < without[1]


def test_a_lowest_point_at_sea_is_zero(tmp_path: Path):
    write_tile(tmp_path, 61, 8)
    (tmp_path / elevation.TILE_LIST).write_text(elevation.tile_name(61, 8) + "\n")
    model = elevation.CopernicusDEM(online=False, directory=tmp_path)
    # Half on the land tile, half on the unpublished (ocean) tile to its west.
    extremes = elevation.park_extremes([[square(7.8, 61.2, 8.2, 61.4)]], dem=model)
    assert extremes is not None
    assert extremes[0] == 0


def test_a_lowest_point_below_the_sea_is_the_sea_surface_not_a_hollow(tmp_path: Path):
    write_tile(tmp_path, 61, 8, fill=-16.0)
    (tmp_path / elevation.TILE_LIST).write_text(elevation.tile_name(61, 8) + "\n")
    model = elevation.CopernicusDEM(online=False, directory=tmp_path)
    extremes = elevation.park_extremes([[square(8.0, 61.4, 8.6, 61.9)]], dem=model)
    assert extremes is not None
    assert extremes[0] == 0


def test_extremes_are_not_stated_over_part_of_a_park(tmp_path: Path):
    write_tile(tmp_path, 61, 8)
    model = elevation.CopernicusDEM(online=False, directory=tmp_path)  # no tile list
    assert elevation.park_extremes([[square(7.8, 61.2, 8.2, 61.4)]], dem=model) is None


def test_attach_fills_only_what_a_guide_does_not_give(dem):
    places = [
        {"id": "no-np-a", "kind": "nationalPark", "facts": {"highestElevationMetres": 2469}},
        {"id": "no-np-b", "kind": "nationalPark"},
        {"id": "no-lvo-c", "kind": "landscapeProtectionArea"},
    ]
    outlines = {
        "no-np-a": [[square(8.2, 61.2, 8.6, 61.6)]],
        "no-np-b": [[square(8.2, 61.2, 8.6, 61.6)]],
        "no-lvo-c": [[square(8.2, 61.2, 8.6, 61.6)]],
    }
    assert elevation.attach_extremes(places, outlines, dem=dem) == 2
    assert places[0]["facts"]["highestElevationMetres"] == 2469
    assert "lowestElevationMetres" in places[0]["facts"]
    assert places[1]["facts"]["elevationNote"] == elevation.NOTE
    assert "facts" not in places[2]


def test_the_credit_and_note_say_what_the_app_shows():
    assert elevation.NOTE == "Measured by Unigrids from Copernicus GLO-30"
    assert elevation.CREDIT.startswith("Copernicus GLO-30 (© DLR e.V. 2010–2014")
    assert "European Union and ESA" in elevation.CREDIT


# --- a pack's grid ----------------------------------------------------------------------


def test_a_pack_grid_reads_back_through_the_us_loader(dem, tmp_path: Path):
    from unigrids_pipeline import dem as us_dem
    from unigrids_pipeline.geo import BoundingBox

    box = BoundingBox(west=8.4, south=61.3, east=8.6, north=61.4)
    index = elevation.write_grid(tmp_path / "grid", box, ground_resolution_m=500.0, dem=dem)
    grid = us_dem.ElevationGrid.load(tmp_path / "grid")
    assert grid.columns == index["columns"]
    assert grid.coverage == 1.0
    value = grid.sample(8.5, 61.35)
    assert value is not None
    assert value == pytest.approx(plane(8.5, 61.35), abs=0.5 + 1e-6 * math.fabs(value))
