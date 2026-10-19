"""The distance and tile maths every measured figure rests on.

These are checked against values worked out another way — a numerically integrated
meridian arc, the closed form for a spherical quadrangle — rather than against numbers
this module produced earlier, which would only pin the current behaviour in place.
"""

import math

from unigrids_pipeline import geo


def test_a_degree_of_longitude_at_the_equator_is_the_semi_major_arc():
    # At the equator the east–west radius of curvature is the semi-major axis itself, so
    # this is the one case with an exact answer to check against.
    expected = geo.EARTH_SEMI_MAJOR_M * math.radians(1.0)
    assert abs(geo.distance_m((0.0, 0.0), (1.0, 0.0)) - expected) < 1e-6
    assert abs(geo.distance_m((0.0, 0.0), (1.0, 0.0)) - 111319.49) < 0.01


def test_a_meridian_arc_matches_numerical_integration():
    # The meridian arc is the integral of the meridional radius of curvature. Integrating
    # it finely is an independent check on the midpoint approximation `distance_m` uses.
    steps = 20000
    integrated = sum(
        geo.meridional_radius_m(37.0 + (index + 0.5) / steps) * math.radians(1.0 / steps)
        for index in range(steps)
    )
    measured = geo.distance_m((-113.0, 37.0), (-113.0, 38.0))
    assert abs(measured - integrated) < 0.5  # under 5 parts per million of 110 km


def test_length_does_not_change_when_a_line_is_subdivided():
    start = (-113.0, 37.2)
    end = (-112.9, 37.3)
    direct = geo.distance_m(start, end)
    steps = 200
    subdivided = [
        (
            start[0] + (end[0] - start[0]) * index / steps,
            start[1] + (end[1] - start[1]) * index / steps,
        )
        for index in range(steps + 1)
    ]
    assert abs(geo.line_length_m(subdivided) - direct) / direct < 1e-5


def test_distance_is_symmetric_and_zero_for_a_point():
    a = (-113.03, 37.27)
    b = (-112.94, 37.31)
    assert geo.distance_m(a, b) == geo.distance_m(b, a)
    assert geo.distance_m(a, a) == 0.0


def test_ring_area_matches_the_closed_form_for_a_spherical_quadrangle():
    # A ring bounded by two meridians and two parallels has an exact area:
    # R² · Δλ · (sin φ_north − sin φ_south).
    west, east, south, north = -113.2, -112.8, 37.1, 37.5
    radius = geo.EARTH_AUTHALIC_RADIUS_M
    expected = (
        radius
        * radius
        * math.radians(east - west)
        * (math.sin(math.radians(north)) - math.sin(math.radians(south)))
    )
    ring = [
        (west, south),
        (east, south),
        (east, north),
        (west, north),
        (west, south),
    ]
    assert abs(geo.ring_area_m2(ring) - expected) / expected < 1e-9


def test_ring_area_ignores_winding_direction():
    ring = [(-113.2, 37.1), (-112.8, 37.1), (-112.8, 37.5), (-113.2, 37.5), (-113.2, 37.1)]
    assert abs(geo.ring_area_m2(ring) - geo.ring_area_m2(list(reversed(ring)))) < 1.0


def test_a_tile_contains_the_coordinate_it_was_chosen_for():
    longitude, latitude = -112.9475, 37.2690  # Zion Canyon
    for zoom in range(0, 17):
        x, y = geo.tile_for_coordinate(longitude, latitude, zoom)
        box = geo.tile_bounds(zoom, x, y)
        assert box.west <= longitude <= box.east
        assert box.south <= latitude <= box.north


def test_tile_resolution_is_the_familiar_web_mercator_ladder():
    # Zoom 0 is one 256-pixel tile across the whole Mercator world.
    assert abs(geo.tile_resolution_m_per_pixel(0, 0.0) - 156543.03392) < 1e-3
    # Each zoom halves it, and latitude shrinks it by the cosine.
    assert abs(
        geo.tile_resolution_m_per_pixel(15, 37.3)
        - 156543.03392 / 2**15 * math.cos(math.radians(37.3))
    ) < 1e-6


def test_flipping_a_tile_row_twice_is_a_round_trip():
    for zoom in (0, 8, 15):
        for y in (0, 1, geo.tile_count(zoom) - 1):
            assert geo.flip_tile_row(zoom, geo.flip_tile_row(zoom, y)) == y


def test_a_bounding_box_buffer_is_a_ground_distance():
    box = geo.BoundingBox(-113.0, 37.2, -112.9, 37.3)
    buffered = box.buffered(2000.0)
    # Two kilometres north of the north edge, measured on the ground.
    north_growth = geo.distance_m((box.west, box.north), (box.west, buffered.north))
    assert abs(north_growth - 2000.0) < 1.0
    # And at least two kilometres east, since longitude padding uses the worst latitude.
    east_growth = geo.distance_m((box.east, box.north), (buffered.east, box.north))
    assert east_growth >= 2000.0 - 1.0


def test_tile_range_covers_the_whole_box():
    box = geo.BoundingBox(-113.2, 37.1, -112.8, 37.5)
    min_x, min_y, max_x, max_y = geo.tile_range(box, 12)
    assert min_x <= max_x and min_y <= max_y
    covered = geo.tile_bounds(12, min_x, min_y).union(geo.tile_bounds(12, max_x, max_y))
    assert covered.west <= box.west and covered.east >= box.east
    assert covered.south <= box.south and covered.north >= box.north
