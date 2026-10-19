"""The trail measurement maths.

These numbers reach the user as facts — "8.2 km, 453 m of climb" on a trail card, and
summed into the hiking totals in Stats. The method in `measure.py` is a set of deliberate
choices (resample at a fixed interval, smooth, then accumulate with a dead band), so
these tests pin the behaviour those choices exist to produce: a steady climb counted in
full, elevation-model noise counted as nothing, and no elevation figure at all where the
model has no data.

The route lines here are synthetic, with lengths worked out from `geo`, so a wrong answer
here is a bug in the measurement rather than a change in somebody's dataset.
"""

import math

import pytest

from unigrids_pipeline import geo, measure


def meridian_line(
    longitude: float = -113.0,
    start_latitude: float = 37.0,
    length_m: float = 4000.0,
    vertices: int = 2,
) -> list[tuple[float, float]]:
    """A straight north-running line of roughly the given ground length."""
    span = math.degrees(length_m / geo.meridional_radius_m(start_latitude))
    return [
        (longitude, start_latitude + span * index / (vertices - 1)) for index in range(vertices)
    ]


def ramp_sampler(line, rise_m: float, fall_m: float, base_m: float = 1200.0):
    """Elevation that climbs then descends, as a function of distance along the line.

    Distance is recomputed from the start with `geo`, so the sampler does not depend on
    how `measure` resampled the line.
    """
    total = geo.line_length_m(line)
    start = line[0]

    def sample(longitude: float, latitude: float) -> float:
        travelled = geo.distance_m(start, (longitude, latitude))
        half = total / 2.0
        if travelled <= half:
            return base_m + rise_m * travelled / half
        return base_m + rise_m - fall_m * (travelled - half) / half

    return sample


# --- resampling --------------------------------------------------------------------


def test_resampling_puts_a_station_every_interval_and_ends_on_the_line():
    line = meridian_line(length_m=1000.0)
    stations = measure.resample(line, interval_m=10.0)
    assert stations[0].distance_m == 0.0
    assert abs(stations[-1].distance_m - geo.line_length_m(line)) < 0.01
    gaps = [
        stations[index + 1].distance_m - stations[index].distance_m
        for index in range(len(stations) - 2)
    ]
    assert all(abs(gap - 10.0) < 1e-6 for gap in gaps)
    assert 100 <= len(stations) <= 102


def test_resampled_stations_stay_on_the_line():
    line = [(-113.0, 37.0), (-112.99, 37.01), (-112.95, 37.0)]
    for station in measure.resample(line, interval_m=25.0):
        assert -113.001 <= station.longitude <= -112.949
        assert 36.999 <= station.latitude <= 37.011


def test_a_degenerate_line_measures_zero_rather_than_raising():
    assert measure.resample([], 10.0) == []
    assert measure.measure([(-113.0, 37.0)]).length_m == 0.0
    assert measure.measure([(-113.0, 37.0), (-113.0, 37.0)]).length_m == 0.0


def test_the_station_interval_must_be_positive():
    with pytest.raises(ValueError):
        measure.resample(meridian_line(), interval_m=0.0)


# --- length ------------------------------------------------------------------------


def test_length_comes_from_the_route_line_and_not_from_its_vertex_count():
    sparse = meridian_line(length_m=8000.0, vertices=2)
    dense = meridian_line(length_m=8000.0, vertices=400)
    sparse_length = measure.measure(sparse).length_m
    dense_length = measure.measure(dense).length_m
    assert abs(sparse_length - 8000.0) < 1.0
    assert abs(sparse_length - dense_length) < 1.0


def test_a_known_route_line_measures_its_known_length():
    # Three legs of 1 km, 2 km and 1.5 km, built from `geo` and measured independently.
    line = [(-113.0, 37.0)]
    for leg in (1000.0, 2000.0, 1500.0):
        last_longitude, last_latitude = line[-1]
        span = math.degrees(leg / geo.meridional_radius_m(last_latitude))
        line.append((last_longitude, last_latitude + span))
    assert abs(measure.measure(line).length_m - 4500.0) < 1.0


# --- gain and loss -----------------------------------------------------------------


def test_a_steady_climb_and_descent_are_counted_in_full():
    line = meridian_line(length_m=5000.0, vertices=2)
    result = measure.measure(line, ramp_sampler(line, rise_m=600.0, fall_m=400.0))
    # The moving average rounds the apex, so a few metres of tolerance, not none.
    assert abs(result.elevation_gain_m - 600.0) < 5.0
    assert abs(result.elevation_loss_m - 400.0) < 5.0
    assert abs(result.high_point_m - 1800.0) < 1.0
    assert abs(result.low_point_m - 1200.0) < 1.0
    assert result.elevation_coverage == 1.0


def test_elevation_model_noise_is_not_counted_as_climb():
    # A flat traverse with a metre of sawtooth noise on it: the dead band should see
    # nothing, where a naive sum of every step would invent hundreds of metres of climb.
    line = meridian_line(length_m=5000.0, vertices=2)
    start = line[0]

    def noisy(longitude: float, latitude: float) -> float:
        travelled = geo.distance_m(start, (longitude, latitude))
        return 1200.0 + 1.4 * math.sin(travelled / 7.0)

    naive_total = 0.0
    stations = measure.resample(line, measure.STATION_INTERVAL_M)
    samples = [noisy(station.longitude, station.latitude) for station in stations]
    for index in range(len(samples) - 1):
        naive_total += max(0.0, samples[index + 1] - samples[index])
    assert naive_total > 150.0  # the mistake this method exists to avoid

    result = measure.measure(line, noisy)
    assert result.elevation_gain_m < 2.0
    assert result.elevation_loss_m < 2.0


def test_a_real_step_just_over_the_threshold_is_kept():
    line = meridian_line(length_m=2000.0, vertices=2)
    start = line[0]

    def step(longitude: float, latitude: float) -> float:
        travelled = geo.distance_m(start, (longitude, latitude))
        return 1200.0 + (12.0 if travelled > 1000.0 else 0.0)

    result = measure.measure(line, step)
    assert abs(result.elevation_gain_m - 12.0) < 1.5
    assert result.elevation_loss_m < 0.5


def test_accumulation_commits_a_whole_run_not_just_the_part_over_the_threshold():
    # 0 -> 100 in one-metre steps: every step is under the dead band, the run is not.
    rising = [float(value) for value in range(101)]
    gain, loss = measure.accumulate_gain_and_loss(rising, threshold_m=3.0)
    assert abs(gain - 100.0) < 1e-9
    assert loss == 0.0


def test_accumulation_is_symmetric_under_reversal():
    series = [0.0, 20.0, 5.0, 60.0, 55.0, 90.0, 10.0]
    gain, loss = measure.accumulate_gain_and_loss(series)
    reversed_gain, reversed_loss = measure.accumulate_gain_and_loss(list(reversed(series)))
    assert abs(gain - reversed_loss) < 1e-9
    assert abs(loss - reversed_gain) < 1e-9


def test_gain_minus_loss_is_the_net_change_whatever_happens_in_between():
    # The property that catches a double-counted run: however the dead band splits a
    # series up, what went up minus what came down has to be where it ended up. Zion's
    # West Rim Trail satisfies it on the real data too (1,404 - 444 = 960 m climbed, over
    # a 965 m spread from its low point to its high).
    series = [1200.0, 1260.0, 1255.0, 1480.0, 1301.0, 1322.0, 1318.0, 1750.0, 1600.0]
    gain, loss = measure.accumulate_gain_and_loss(series)
    assert abs((gain - loss) - (series[-1] - series[0])) < 3.0


def test_a_closed_loop_climbs_and_descends_the_same_amount():
    series = [0.0, 50.0, 120.0, 80.0, 200.0, 40.0, 0.0]
    gain, loss = measure.accumulate_gain_and_loss(series)
    assert abs(gain - loss) < 1e-9


def test_wobbles_under_the_dead_band_do_not_break_a_run_in_two():
    # A climb interrupted by a two-metre dip is still one climb of 100 m.
    series = [0.0, 40.0, 38.0, 70.0, 68.5, 100.0]
    gain, loss = measure.accumulate_gain_and_loss(series, threshold_m=3.0)
    assert abs(gain - 100.0) < 1e-9
    assert loss == 0.0


def test_a_series_with_one_or_no_points_has_no_climb():
    assert measure.accumulate_gain_and_loss([]) == (0.0, 0.0)
    assert measure.accumulate_gain_and_loss([1200.0]) == (0.0, 0.0)


# --- smoothing ---------------------------------------------------------------------


def test_smoothing_keeps_the_ends_where_they_are_rather_than_padding_them():
    values = [0.0, 10.0, 20.0, 30.0, 40.0]
    smoothed = measure.smooth(values, window=3)
    assert smoothed[0] == pytest.approx(5.0)  # mean of the first two, not of three
    assert smoothed[-1] == pytest.approx(35.0)
    assert len(smoothed) == len(values)


def test_smoothing_with_a_window_of_one_changes_nothing():
    values = [1.0, 7.0, 3.0]
    assert measure.smooth(values, window=1) == values


# --- profile and slope length ------------------------------------------------------


def test_the_profile_spans_the_trail_and_is_small_enough_to_ship():
    line = meridian_line(length_m=9000.0, vertices=2)
    result = measure.measure(line, ramp_sampler(line, rise_m=700.0, fall_m=700.0))
    assert len(result.profile) == measure.PROFILE_SAMPLE_COUNT
    assert result.profile[0].distance_m == 0.0
    assert abs(result.profile[-1].distance_m - result.length_m) < 1.0
    distances = [point.distance_m for point in result.profile]
    assert distances == sorted(distances)
    assert max(point.elevation_m for point in result.profile) <= result.high_point_m + 0.5


def test_a_short_trail_keeps_every_station_in_its_profile():
    line = meridian_line(length_m=300.0, vertices=2)
    result = measure.measure(line, ramp_sampler(line, rise_m=30.0, fall_m=30.0))
    assert len(result.profile) == result.station_count


def test_slope_length_is_longer_than_map_length_on_a_climb():
    line = meridian_line(length_m=3000.0, vertices=2)
    result = measure.measure(line, ramp_sampler(line, rise_m=500.0, fall_m=0.0))
    assert result.slope_length_m > result.length_m
    # And not by much: 500 m over 3 km is a 1.4 % correction.
    assert result.slope_length_m / result.length_m < 1.05


# --- missing elevation -------------------------------------------------------------


def test_without_an_elevation_model_the_length_still_comes_back():
    result = measure.measure(meridian_line(length_m=2000.0))
    assert abs(result.length_m - 2000.0) < 1.0
    assert result.elevation_gain_m is None
    assert result.profile == []
    assert not result.has_elevation


def test_a_partly_covered_trail_reports_no_elevation_rather_than_a_partial_figure():
    line = meridian_line(length_m=4000.0, vertices=2)
    full = ramp_sampler(line, rise_m=400.0, fall_m=0.0)
    midpoint_latitude = (line[0][1] + line[-1][1]) / 2.0

    def patchy(longitude: float, latitude: float) -> float | None:
        return None if latitude > midpoint_latitude else full(longitude, latitude)

    result = measure.measure(line, patchy)
    assert result.elevation_gain_m is None
    assert result.high_point_m is None
    assert 0.0 < result.elevation_coverage < 1.0
    assert abs(result.length_m - 4000.0) < 1.0
