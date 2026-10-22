"""Choosing a pack's tiles, and writing them.

Both halves of the pilot's open question live here: how many tiles a park's shape needs
(``coverage``) and what a pack costs to store them in (``mbtiles``). An error in either
would move the 4 GB answer without moving anything a user can see.
"""

import math

from unigrids_pipeline import coverage, mbtiles
from unigrids_pipeline.geo import BoundingBox, flip_tile_row, tile_bounds


def square_boundary(
    west: float = -113.0, south: float = 37.0, side_degrees: float = 0.1
) -> list[dict]:
    east, north = west + side_degrees, south + side_degrees
    return [
        {
            "type": "Feature",
            "geometry": {
                "type": "Polygon",
                "coordinates": [
                    [[west, south], [east, south], [east, north], [west, north], [west, south]]
                ],
            },
        }
    ]


def l_shaped_boundary() -> list[dict]:
    """An L: the shape that makes clipping worth doing, since its box is half empty."""
    return [
        {
            "type": "Feature",
            "geometry": {
                "type": "Polygon",
                "coordinates": [
                    [
                        [-113.0, 37.0],
                        [-112.6, 37.0],
                        [-112.6, 37.05],
                        [-112.95, 37.05],
                        [-112.95, 37.4],
                        [-113.0, 37.4],
                        [-113.0, 37.0],
                    ]
                ],
            },
        }
    ]


# --- rings and area ----------------------------------------------------------------


def test_a_polygon_with_a_hole_has_the_hole_taken_out_of_its_area():
    outer = [[-113.0, 37.0], [-112.8, 37.0], [-112.8, 37.2], [-113.0, 37.2], [-113.0, 37.0]]
    inner = [
        [-112.95, 37.05],
        [-112.85, 37.05],
        [-112.85, 37.15],
        [-112.95, 37.15],
        [-112.95, 37.05],
    ]
    with_hole = coverage.rings(
        [{"geometry": {"type": "Polygon", "coordinates": [outer, inner]}}]
    )
    without = coverage.rings([{"geometry": {"type": "Polygon", "coordinates": [outer]}}])
    assert any(ring.is_hole for ring in with_hole)
    assert coverage.area_km2(with_hole) < coverage.area_km2(without)


def test_multipolygon_parts_add_up():
    square = square_boundary()[0]["geometry"]["coordinates"]
    other = square_boundary(west=-112.0)[0]["geometry"]["coordinates"]
    multi = coverage.rings(
        [{"geometry": {"type": "MultiPolygon", "coordinates": [square, other]}}]
    )
    single = coverage.rings([{"geometry": {"type": "Polygon", "coordinates": square}}])
    assert abs(coverage.area_km2(multi) - 2 * coverage.area_km2(single)) < 1.0


def test_geometry_that_is_not_a_polygon_is_ignored_rather_than_crashing():
    assert coverage.rings([{"geometry": {"type": "Point", "coordinates": [0, 0]}}]) == []
    assert coverage.rings([{}]) == []


# --- tile selection ----------------------------------------------------------------


def test_every_chosen_tile_touches_the_park_or_its_buffer():
    park = coverage.ParkCoverage(
        coverage.rings(square_boundary()), buffer_m=1000.0, max_zoom=14
    )
    box = park.render_bounds
    for x, y in park.tiles(13):
        bounds = tile_bounds(13, x, y)
        assert bounds.west <= box.east and bounds.east >= box.west
        assert bounds.south <= box.north and bounds.north >= box.south


def test_clipping_to_the_boundary_beats_rendering_the_bounding_box():
    park = coverage.ParkCoverage(
        coverage.rings(l_shaped_boundary()), buffer_m=500.0, max_zoom=14
    )
    clipped = park.tile_counts([14])[14]
    boxed = park.bounding_box_tile_counts([14])[14]
    assert clipped < boxed
    # The L fills well under two thirds of its box, and the tiles should show it.
    assert clipped / boxed < 0.75


def test_a_bigger_buffer_never_means_fewer_tiles():
    rings = coverage.rings(square_boundary())
    tight = coverage.ParkCoverage(rings, buffer_m=200.0, max_zoom=14).tile_counts([13])[13]
    loose = coverage.ParkCoverage(rings, buffer_m=4000.0, max_zoom=14).tile_counts([13])[13]
    assert loose > tight


def test_tile_counts_roughly_quadruple_with_each_zoom():
    park = coverage.ParkCoverage(
        coverage.rings(square_boundary(side_degrees=0.3)), buffer_m=1000.0, max_zoom=15
    )
    counts = park.tile_counts([12, 13, 14, 15])
    for zoom in (13, 14, 15):
        ratio = counts[zoom] / counts[zoom - 1]
        assert 3.2 < ratio < 4.8, f"z{zoom} grew by {ratio:.2f}"


def test_a_park_needs_a_boundary():
    try:
        coverage.ParkCoverage([], buffer_m=1000.0, max_zoom=14)
    except ValueError:
        return
    raise AssertionError("a coverage without rings should refuse to be built")


def test_trails_outside_the_boundary_can_widen_the_rendered_extent():
    rings = coverage.rings(square_boundary())
    plain = coverage.ParkCoverage(rings, buffer_m=500.0, max_zoom=13)
    extra = BoundingBox(-113.3, 37.0, -113.0, 37.1)
    widened = coverage.ParkCoverage(rings, buffer_m=500.0, max_zoom=13, extra=extra)
    assert widened.render_bounds.west < plain.render_bounds.west


# --- writing the pack --------------------------------------------------------------


def test_tiles_come_back_under_the_row_order_mbtiles_expects(tmp_path):
    import sqlite3

    path = tmp_path / "tiles.mbtiles"
    with mbtiles.MBTilesWriter(path) as writer:
        writer.add(12, 761, 1591, b"a tile")
        writer.describe(
            name="Test",
            description="Test",
            tile_format="webp",
            bounds=BoundingBox(-113.0, 37.0, -112.9, 37.1),
            min_zoom=12,
            max_zoom=12,
            attribution="© OpenStreetMap contributors",
        )

    connection = sqlite3.connect(path)
    row = connection.execute("SELECT tile_column, tile_row FROM tiles").fetchone()
    assert row == (761, flip_tile_row(12, 1591))
    metadata = dict(connection.execute("SELECT name, value FROM metadata"))
    assert metadata["format"] == "webp"
    # MBTiles rows are TMS by definition; a "scheme" key saying otherwise made other
    # readers draw the pack upside down.
    assert "scheme" not in metadata
    assert "OpenStreetMap" in metadata["attribution"]
    connection.close()


def test_a_quantised_png_is_still_a_png_as_far_as_mbtiles_is_concerned(tmp_path):
    import sqlite3

    path = tmp_path / "tiles.mbtiles"
    with mbtiles.MBTilesWriter(path) as writer:
        writer.add(10, 1, 1, b"x")
        writer.describe(
            name="Test",
            description="Test",
            tile_format="png8",
            bounds=BoundingBox(-113.0, 37.0, -112.9, 37.1),
            min_zoom=10,
            max_zoom=10,
            attribution="",
        )
    connection = sqlite3.connect(path)
    assert dict(connection.execute("SELECT name, value FROM metadata"))["format"] == "png"
    connection.close()


def test_the_writer_counts_what_it_wrote(tmp_path):
    with mbtiles.MBTilesWriter(tmp_path / "tiles.mbtiles") as writer:
        writer.add(12, 1, 1, b"12345")
        writer.add(12, 1, 2, b"123")
        writer.add(13, 1, 1, b"1")
        by_zoom = writer.bytes_by_zoom()
        assert by_zoom[12] == {
            "tiles": 2,
            "bytes": 8,
            "smallest_tile_bytes": 3,
            "largest_tile_bytes": 5,
        }
        assert by_zoom[13]["tiles"] == 1
        assert writer.tile_count == 3
        assert writer.tile_bytes == 9


def test_modelled_state_park_tiles_grow_with_the_park(tmp_path):
    from unigrids_pipeline import config, sizereport

    settings = config.DEFAULT_PACK_SETTINGS
    small = sizereport.modelled_tiles(10, 15, settings)
    large = sizereport.modelled_tiles(100, 15, settings)
    assert large > small
    # The buffer dominates a small park: ten times the area is far less than ten times
    # the tiles, and the report's state-park table has to be read with that in mind.
    assert large < 10 * small


def test_a_zoom_policy_gives_the_deepest_zooms_only_to_the_smaller_parks():
    from unigrids_pipeline import sizereport

    policy = sizereport.ZoomPolicy(
        "tiered", 10, 16, area_tiers=((2_000.0, 16), (10_000.0, 15), (math.inf, 14))
    )
    assert max(policy.zooms_for(600.0)) == 16
    assert max(policy.zooms_for(5_000.0)) == 15
    assert max(policy.zooms_for(60_000.0)) == 14
    assert min(policy.zooms_for(600.0)) == 10


def test_a_flat_zoom_policy_treats_every_park_the_same():
    from unigrids_pipeline import sizereport

    policy = sizereport.ZoomPolicy("z10-15", 10, 15)
    assert policy.zooms_for(1.0) == policy.zooms_for(100_000.0) == list(range(10, 16))


def test_deepest_zoom_follows_the_park_area():
    from unigrids_pipeline import config

    assert config.max_zoom_for_area(600) == 16  # Zion
    assert config.max_zoom_for_area(2_114) == 15  # Great Smoky Mountains
    assert config.max_zoom_for_area(8_983) == 15  # Yellowstone
    assert config.max_zoom_for_area(53_000) == 13  # Wrangell–St. Elias


def test_any_national_park_can_be_built_by_code():
    from unigrids_pipeline import config

    assert config.park("ZION").place_id == "np-zion"
    assert config.park("glac").place_id == "np-glacier"
