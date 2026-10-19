"""Joining the trails dataset's segments into trails, and measuring what comes out.

The NPS layer publishes segments: Zion's Watchman Trail is two features, its visitor
centre pathways are twelve. A trail card shows one length and one profile, so the joining
has to be right before the measuring means anything — and a join that silently merged two
unrelated paths would produce a trail nobody can walk, stated to the metre.
"""

import math

from unigrids_pipeline import geo, trails


def line(*points: tuple[float, float]) -> list[tuple[float, float]]:
    return [(float(longitude), float(latitude)) for longitude, latitude in points]


def feature(
    coordinates: list[tuple[float, float]], name: str = "Test Trail", **properties: object
) -> dict:
    return {
        "type": "Feature",
        "properties": {"TRLNAME": name, "TRLSTATUS": "Existing", **properties},
        "geometry": {"type": "LineString", "coordinates": [list(point) for point in coordinates]},
    }


def north_line(
    start: tuple[float, float], length_m: float, steps: int = 2
) -> list[tuple[float, float]]:
    span = math.degrees(length_m / geo.meridional_radius_m(start[1]))
    return [(start[0], start[1] + span * index / (steps - 1)) for index in range(steps)]


# --- joining -----------------------------------------------------------------------


def test_segments_that_meet_end_to_end_become_one_chain():
    first = north_line((-113.0, 37.0), 500.0)
    second = north_line(first[-1], 500.0)
    chains = trails.chain([{"coordinates": first}, {"coordinates": second}])
    assert len(chains) == 1
    assert abs(geo.line_length_m(chains[0]) - 1000.0) < 2.0


def test_a_segment_digitised_backwards_is_turned_round_rather_than_dropped():
    first = north_line((-113.0, 37.0), 400.0)
    second = list(reversed(north_line(first[-1], 400.0)))
    chains = trails.chain([{"coordinates": first}, {"coordinates": second}])
    assert len(chains) == 1
    assert abs(geo.line_length_m(chains[0]) - 800.0) < 2.0


def test_segments_that_do_not_meet_stay_separate_parts():
    first = north_line((-113.0, 37.0), 300.0)
    far_away = north_line((-112.5, 37.2), 300.0)
    chains = trails.chain([{"coordinates": first}, {"coordinates": far_away}])
    assert len(chains) == 2


def test_chains_come_back_longest_first():
    short = north_line((-113.0, 37.0), 100.0, steps=3)
    long = north_line((-112.5, 37.2), 900.0, steps=40)
    chains = trails.chain([{"coordinates": short}, {"coordinates": long}])
    assert len(chains[0]) > len(chains[1])


def test_joining_only_happens_within_the_tolerance():
    first = north_line((-113.0, 37.0), 300.0)
    # A hundred metres further on: a real gap, not a digitising seam.
    second = north_line((first[-1][0], first[-1][1] + 0.001), 300.0)
    assert len(trails.chain([{"coordinates": first}, {"coordinates": second}])) == 2


# --- grouping ----------------------------------------------------------------------


def test_segments_are_grouped_by_trail_name():
    segments = trails.segments_of(
        [
            feature(north_line((-113.0, 37.0), 100.0), "Watchman Trail"),
            feature(north_line((-113.0, 37.01), 100.0), "Watchman Trail"),
            feature(north_line((-113.0, 37.02), 100.0), "Riverside Walk"),
        ]
    )
    grouped = trails.group_by_name(segments)
    assert sorted(grouped) == ["Riverside Walk", "Watchman Trail"]
    assert len(grouped["Watchman Trail"]) == 2


def test_unnamed_segments_do_not_merge_into_one_imaginary_trail():
    segments = trails.segments_of(
        [
            feature(north_line((-113.0, 37.0), 100.0), "", GEOMETRYID="{AAAA1111-0000}"),
            feature(north_line((-112.0, 38.0), 100.0), "", GEOMETRYID="{BBBB2222-0000}"),
        ]
    )
    assert len(trails.group_by_name(segments)) == 2


def test_decommissioned_segments_are_left_out():
    segments = trails.segments_of(
        [
            feature(north_line((-113.0, 37.0), 100.0), "Open Trail"),
            feature(north_line((-113.0, 37.01), 100.0), "Old Trail", TRLSTATUS="Decommissioned"),
        ]
    )
    assert [segment["properties"]["TRLNAME"] for segment in segments] == ["Open Trail"]


def test_multilinestring_geometry_is_flattened_into_segments():
    multi = {
        "type": "Feature",
        "properties": {"TRLNAME": "Split Trail", "TRLSTATUS": "Existing"},
        "geometry": {
            "type": "MultiLineString",
            "coordinates": [
                [list(point) for point in north_line((-113.0, 37.0), 100.0)],
                [list(point) for point in north_line((-113.0, 37.05), 100.0)],
            ],
        },
    }
    assert len(trails.segments_of([multi])) == 2


# --- measuring the result ----------------------------------------------------------


def flat_at(elevation: float):
    return lambda longitude, latitude: elevation


def test_a_trail_split_across_segments_measures_as_one_trail():
    first = north_line((-113.0, 37.0), 600.0)
    second = north_line(first[-1], 400.0)
    derived = trails.derive_trails(
        [feature(first, "Watchman Trail"), feature(second, "Watchman Trail")],
        place_id="np-zion",
        place_slug="zion",
        sample_elevation=flat_at(1200.0),
    )
    assert len(derived) == 1
    trail = derived[0]
    assert trail.id == "trail-zion-watchman-trail"
    assert trail.placeID == "np-zion"
    assert abs(trail.lengthMetres - 1000.0) < 2.0
    assert len(trail.parts) == 1
    assert trail.segmentCount == 2
    assert trail.gainMetres == 0.0


def test_a_branching_trail_is_reported_as_several_parts_not_one_long_walk():
    spine = north_line((-113.0, 37.0), 500.0)
    detached = north_line((-112.9, 37.1), 300.0)
    derived = trails.derive_trails(
        [feature(spine, "Forked Trail"), feature(detached, "Forked Trail")],
        place_id="np-zion",
        place_slug="zion",
        sample_elevation=flat_at(1200.0),
    )
    trail = derived[0]
    assert len(trail.parts) == 2
    assert abs(trail.lengthMetres - 800.0) < 2.0
    payload = trail.as_json()
    assert payload["partCount"] == 2
    # The stored profile belongs to the longest part, and says which one it is.
    assert payload["profilePartIndex"] == 0


def test_an_unmeasurable_trail_carries_no_elevation_figures_at_all():
    derived = trails.derive_trails(
        [feature(north_line((-113.0, 37.0), 500.0), "Nowhere Trail")],
        place_id="np-zion",
        place_slug="zion",
        sample_elevation=lambda longitude, latitude: None,
    )
    payload = derived[0].as_json()
    assert "gainMetres" not in payload
    assert "highPointMetres" not in payload
    assert payload["lengthMetres"] > 0
    assert payload["elevationCoverage"] == 0.0


def test_the_pack_records_how_its_trails_were_measured():
    method = trails.measurement_method()
    assert method["stationIntervalMetres"] > 0
    assert method["gainThresholdMetres"] > 0
    # And is explicit about what it did not work out.
    assert "difficulty" in method["notDerivedYet"]
    assert "routeType" in method["notDerivedYet"]
