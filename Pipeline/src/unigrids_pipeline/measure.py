"""Trail measurement: length, elevation gain and loss, and the profile.

`SPECIFICATION.md` §8: *"Length, elevation and profile are computed in the pipeline from
the route line and USGS elevation data, so every trail is measured the same way."* That
sentence is the whole reason this module exists. Sources disagree wildly about how long a
trail is — a park sign, a trail wiki and a GPS track of the same path routinely differ by
a fifth — and most of the disagreement is method, not measurement: who smoothed, who
counted a one-metre bump as climb, who followed the slope and who read the map.

So the method is fixed here, written down, and applied to every trail in every park:

1. **Resample** the route line to a station every :data:`STATION_INTERVAL_M`. Elevation
   sampled at the source's own vertices would weight the answer by how carefully each
   park's GIS staff digitised that trail.
2. **Sample** the elevation model bilinearly at each station.
3. **Smooth** with a centred moving average over :data:`SMOOTHING_WINDOW_M`. A 10 m DEM
   has metre-scale vertical noise, and summed over ten thousand stations noise alone
   invents hundreds of metres of climb.
4. **Accumulate** gain and loss with a :data:`HYSTERESIS_THRESHOLD_M` dead band: a rise
   only counts once it has gone that far above the last turning point. This is what stops
   a flat canyon floor from reading as rolling hills.

Horizontal length is the number quoted (that is what a trail sign means); the
slope-following length is reported next to it rather than blended into it.
"""

from __future__ import annotations

from collections.abc import Callable, Sequence
from dataclasses import dataclass, field

from .geo import Coordinate, distance_m, line_length_m

STATION_INTERVAL_M = 10.0
"""Spacing of the resampled stations, matched to 3DEP's ~10 m posting at 1/3 arc-second.
Sampling finer would invent detail the elevation model does not contain."""

SMOOTHING_WINDOW_M = 50.0
"""Width of the centred moving average applied to the elevation series."""

HYSTERESIS_THRESHOLD_M = 3.0
"""A rise or fall smaller than this is treated as elevation-model noise and not counted.
3DEP's documented vertical accuracy is of this order, and the dead band is the usual
remedy."""

PROFILE_SAMPLE_COUNT = 120
"""Points kept in the stored profile. Enough for a chart on a phone, small enough that a
park's worth of profiles stays a rounding error next to the tiles."""

ElevationSampler = Callable[[float, float], float | None]
"""``(longitude, latitude) -> metres above sea level``, or ``None`` where it has no data."""


@dataclass(frozen=True)
class Station:
    """One resampled point along a route line."""

    longitude: float
    latitude: float
    distance_m: float


@dataclass(frozen=True)
class ProfilePoint:
    distance_m: float
    elevation_m: float


@dataclass(frozen=True)
class Measurement:
    """What the pipeline knows about a route line once it has measured it.

    Every figure here is derived. Nothing is carried over from what a source claimed, and
    where the elevation model has no data the elevation figures are ``None`` rather than
    a guess (``AGENTS.md`` §4).
    """

    length_m: float
    station_count: int
    elevation_gain_m: float | None = None
    elevation_loss_m: float | None = None
    high_point_m: float | None = None
    low_point_m: float | None = None
    slope_length_m: float | None = None
    profile: list[ProfilePoint] = field(default_factory=list)
    elevation_coverage: float = 0.0
    """Fraction of stations the elevation model could answer for, 0.0 to 1.0."""

    @property
    def has_elevation(self) -> bool:
        return self.elevation_gain_m is not None


def resample(line: Sequence[Coordinate], interval_m: float = STATION_INTERVAL_M) -> list[Station]:
    """Stations every ``interval_m`` along a polyline, plus both endpoints.

    The final station lands on the line's last vertex rather than at a round distance, so
    the station distances always end at the line's true length.
    """
    if interval_m <= 0:
        raise ValueError("the station interval must be positive")
    cleaned = _drop_repeated_vertices(line)
    if not cleaned:
        return []
    if len(cleaned) == 1:
        longitude, latitude = cleaned[0]
        return [Station(longitude, latitude, 0.0)]

    stations = [Station(cleaned[0][0], cleaned[0][1], 0.0)]
    travelled = 0.0
    next_station_at = interval_m

    for index in range(len(cleaned) - 1):
        start = cleaned[index]
        end = cleaned[index + 1]
        segment_length = distance_m(start, end)
        if segment_length <= 0.0:
            continue
        segment_end = travelled + segment_length
        while next_station_at <= segment_end:
            fraction = (next_station_at - travelled) / segment_length
            stations.append(
                Station(
                    start[0] + (end[0] - start[0]) * fraction,
                    start[1] + (end[1] - start[1]) * fraction,
                    next_station_at,
                )
            )
            next_station_at += interval_m
        travelled = segment_end

    last = cleaned[-1]
    if travelled - stations[-1].distance_m > interval_m * 1e-6:
        stations.append(Station(last[0], last[1], travelled))
    return stations


def smooth(values: Sequence[float], window: int) -> list[float]:
    """Centred moving average, shrinking the window at the ends rather than padding.

    Padding with the edge value would flatten the first and last stations, and a
    trailhead is exactly where a trail's steepest ground tends to be.
    """
    if window <= 1 or len(values) <= 1:
        return list(values)
    half = window // 2
    smoothed: list[float] = []
    for index in range(len(values)):
        start = max(0, index - half)
        end = min(len(values), index + half + 1)
        window_values = values[start:end]
        smoothed.append(sum(window_values) / len(window_values))
    return smoothed


def accumulate_gain_and_loss(
    elevations: Sequence[float],
    threshold_m: float = HYSTERESIS_THRESHOLD_M,
) -> tuple[float, float]:
    """Total rise and total fall along a series, ignoring wobbles under ``threshold_m``.

    Hysteresis, not a per-step filter: the series' direction only reverses once it has
    moved ``threshold_m`` back from the extreme it reached, and the whole run up to that
    extreme is then committed at once. A steady climb is therefore counted in full, however
    many steps it takes, while a flat traverse jittering by a metre counts as nothing.
    """
    if len(elevations) < 2:
        return 0.0, 0.0

    gain = 0.0
    loss = 0.0
    pivot = elevations[0]
    extreme = elevations[0]
    lowest = elevations[0]
    highest = elevations[0]
    direction = 0

    for value in elevations[1:]:
        if direction == 0:
            lowest = min(lowest, value)
            highest = max(highest, value)
            if value - lowest >= threshold_m:
                direction = 1
                pivot = lowest
                extreme = value
            elif highest - value >= threshold_m:
                direction = -1
                pivot = highest
                extreme = value
        elif direction == 1:
            if value > extreme:
                extreme = value
            elif extreme - value >= threshold_m:
                gain += extreme - pivot
                pivot = extreme
                extreme = value
                direction = -1
        elif value < extreme:
            extreme = value
        elif value - extreme >= threshold_m:
            loss += pivot - extreme
            pivot = extreme
            extreme = value
            direction = 1

    if direction == 1:
        gain += max(0.0, extreme - pivot)
    elif direction == -1:
        loss += max(0.0, pivot - extreme)
    return gain, loss


def measure(
    line: Sequence[Coordinate],
    sample_elevation: ElevationSampler | None = None,
    *,
    interval_m: float = STATION_INTERVAL_M,
    smoothing_window_m: float = SMOOTHING_WINDOW_M,
    threshold_m: float = HYSTERESIS_THRESHOLD_M,
    profile_points: int = PROFILE_SAMPLE_COUNT,
) -> Measurement:
    """Measure one route line. The one entry point, so every trail is measured alike.

    Without a sampler, or where the elevation model has no data for part of the line, the
    length still comes back and the elevation figures are ``None``. A partly covered trail
    is reported as uncovered rather than measured over the covered part, because a gain
    figure for two thirds of a trail reads to the user as the gain for all of it.
    """
    stations = resample(line, interval_m)
    if len(stations) < 2:
        return Measurement(
            length_m=line_length_m(_drop_repeated_vertices(line)),
            station_count=len(stations),
        )

    length = stations[-1].distance_m
    if sample_elevation is None:
        return Measurement(length_m=length, station_count=len(stations))

    raw: list[float | None] = [
        sample_elevation(station.longitude, station.latitude) for station in stations
    ]
    covered = [value for value in raw if value is not None]
    coverage = len(covered) / len(raw)
    if len(covered) != len(raw):
        return Measurement(
            length_m=length,
            station_count=len(stations),
            elevation_coverage=coverage,
        )

    elevations = [float(value) for value in raw if value is not None]
    window = max(1, round(smoothing_window_m / interval_m))
    smoothed = smooth(elevations, window)
    gain, loss = accumulate_gain_and_loss(smoothed, threshold_m)

    return Measurement(
        length_m=length,
        station_count=len(stations),
        elevation_gain_m=gain,
        elevation_loss_m=loss,
        # High and low points come from the unsmoothed samples: they are elevations of real
        # ground at a station, and the moving average would shave a few metres off a summit.
        high_point_m=max(elevations),
        low_point_m=min(elevations),
        slope_length_m=_slope_length_m(stations, smoothed),
        profile=_profile(stations, smoothed, profile_points),
        elevation_coverage=coverage,
    )


def _slope_length_m(stations: Sequence[Station], elevations: Sequence[float]) -> float:
    """Length along the slope rather than across the map.

    Measured from the smoothed series, because on a 10 m model the raw one would add
    length out of noise. Reported separately: a trail sign quotes map length.
    """
    total = 0.0
    for index in range(len(stations) - 1):
        horizontal = stations[index + 1].distance_m - stations[index].distance_m
        vertical = elevations[index + 1] - elevations[index]
        total += (horizontal * horizontal + vertical * vertical) ** 0.5
    return total


def _profile(
    stations: Sequence[Station], elevations: Sequence[float], points: int
) -> list[ProfilePoint]:
    """Thin the series to a fixed number of evenly spaced points for the chart."""
    if points < 2 or len(stations) <= points:
        return [
            ProfilePoint(round(station.distance_m, 1), round(elevation, 1))
            for station, elevation in zip(stations, elevations, strict=True)
        ]
    length = stations[-1].distance_m
    profile: list[ProfilePoint] = []
    for step in range(points):
        target = length * step / (points - 1)
        index = min(
            range(len(stations)),
            key=lambda candidate: abs(stations[candidate].distance_m - target),
        )
        profile.append(ProfilePoint(round(target, 1), round(elevations[index], 1)))
    return profile


def _drop_repeated_vertices(line: Sequence[Coordinate]) -> list[Coordinate]:
    """Drop exact duplicates, which the trails dataset has where segments were joined."""
    cleaned: list[Coordinate] = []
    for point in line:
        if not cleaned or point != cleaned[-1]:
            cleaned.append((float(point[0]), float(point[1])))
    return cleaned
