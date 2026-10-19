"""Turning the NPS trails layer into measured trails.

The dataset is segments, not trails. Zion's "Visitor Center Area Pathways" is twelve
separate features; the West Rim Trail is one; Watchman Trail is two, split where a bridge
was digitised separately. A hiker thinks in trails, and the trail card in the app shows
one length and one profile, so segments have to be joined before they are measured.

Joining is done by geometry, not by trust: segments sharing a name are chained end to end
wherever their endpoints meet within :data:`JOIN_TOLERANCE_M`. A named trail that branches
comes out as more than one chain, and the trail then honestly reports several parts rather
than a total nobody could walk in one go.

What this module does *not* do is decide difficulty, route type, features or the sights
along the way. Those are the rest of ``derive``'s contract and they need more than the
route line — a loop and an out-and-back are the same geometry walked differently. The
pack records them as not yet derived rather than guessing (``AGENTS.md`` §4).
"""

from __future__ import annotations

from collections.abc import Iterable, Sequence
from dataclasses import dataclass, field
from typing import Any

from . import ids, measure
from .geo import Coordinate, distance_m, line_length_m
from .measure import ElevationSampler, Measurement

JOIN_TOLERANCE_M = 15.0
"""How close two segment ends have to be to count as the same point. The trails layer's
own XY accuracy is coarser than this where it is recorded at all."""

# Segments the catalogue should not carry. Everything else is kept, including the oddities
# ("Bridge", "Pathways"), because a park's GIS staff put them in the public layer on
# purpose and the app can filter what it does not want to list.
EXCLUDED_STATUSES = frozenset({"Decommissioned", "Temporarily Closed", "Proposed"})


@dataclass
class TrailPart:
    """One walkable chain of segments."""

    coordinates: list[Coordinate]
    measurement: Measurement | None = None


@dataclass
class DerivedTrail:
    """A named trail with its measured figures.

    Field names follow the Swift ``Trail`` type's, so the app decodes this without a
    translation layer. ``difficulty`` and ``routeType`` are absent on purpose: they are not
    derived yet.
    """

    id: str
    placeID: str  # noqa: N815 - matches the Swift property name the app decodes
    name: str
    lengthMetres: float  # noqa: N815
    parts: list[TrailPart] = field(default_factory=list)
    gainMetres: float | None = None  # noqa: N815
    lossMetres: float | None = None  # noqa: N815
    highPointMetres: float | None = None  # noqa: N815
    lowPointMetres: float | None = None  # noqa: N815
    slopeLengthMetres: float | None = None  # noqa: N815
    profile: list[dict[str, float]] = field(default_factory=list)
    profilePartIndex: int = 0  # noqa: N815
    segmentCount: int = 0  # noqa: N815
    elevationCoverage: float = 0.0  # noqa: N815
    source: dict[str, Any] = field(default_factory=dict)

    def as_json(self) -> dict[str, Any]:
        """The pack's record. Nothing unmeasured is given a number."""
        payload: dict[str, Any] = {
            "id": self.id,
            "placeID": self.placeID,
            "name": self.name,
            "lengthMetres": round(self.lengthMetres, 1),
            "partCount": len(self.parts),
            "segmentCount": self.segmentCount,
            "source": self.source,
        }
        if self.gainMetres is not None:
            payload |= {
                "gainMetres": round(self.gainMetres, 1),
                "lossMetres": round(self.lossMetres or 0.0, 1),
                "highPointMetres": round(self.highPointMetres or 0.0, 1),
                "lowPointMetres": round(self.lowPointMetres or 0.0, 1),
                "slopeLengthMetres": round(self.slopeLengthMetres or 0.0, 1),
                "profile": self.profile,
                "profilePartIndex": self.profilePartIndex,
            }
        else:
            payload["elevationCoverage"] = round(self.elevationCoverage, 3)
        return payload


def segments_of(features: Iterable[dict[str, Any]]) -> list[dict[str, Any]]:
    """Usable trail segments, with their geometry flattened to single lines."""
    segments: list[dict[str, Any]] = []
    for feature in features:
        properties = feature.get("properties") or {}
        if (properties.get("TRLSTATUS") or "") in EXCLUDED_STATUSES:
            continue
        geometry = feature.get("geometry") or {}
        kind = geometry.get("type")
        if kind == "LineString":
            lines = [geometry.get("coordinates") or []]
        elif kind == "MultiLineString":
            lines = list(geometry.get("coordinates") or [])
        else:
            continue
        for line in lines:
            coordinates = [(float(point[0]), float(point[1])) for point in line if len(point) >= 2]
            if len(coordinates) >= 2:
                segments.append({"properties": properties, "coordinates": coordinates})
    return segments


def group_by_name(segments: Sequence[dict[str, Any]]) -> dict[str, list[dict[str, Any]]]:
    """Segments keyed by trail name, falling back to the feature's own stable GIS id.

    An unnamed segment gets its own entry rather than joining an "unnamed" blob: they are
    unrelated bits of ground, and merging them would produce a trail that does not exist.
    """
    grouped: dict[str, list[dict[str, Any]]] = {}
    for segment in segments:
        properties = segment["properties"]
        name = (properties.get("TRLNAME") or "").strip()
        if not name:
            geometry_id = (properties.get("GEOMETRYID") or "").strip("{}")
            name = f"Unnamed trail {geometry_id[:8] or properties.get('OBJECTID', '')}"
        grouped.setdefault(name, []).append(segment)
    return grouped


def chain(
    segments: Sequence[dict[str, Any]], tolerance_m: float = JOIN_TOLERANCE_M
) -> list[list[Coordinate]]:
    """Join segments into the longest chains their endpoints allow.

    Greedy: take any unused segment, then keep extending both ends with whatever still
    meets them. Greedy is the right amount of cleverness here — at a junction of three
    segments with one name there is no correct answer, only a choice, and the result is
    reported as parts either way.
    """
    remaining = [list(segment["coordinates"]) for segment in segments]
    chains: list[list[Coordinate]] = []

    while remaining:
        current = remaining.pop()
        extended = True
        while extended:
            extended = False
            for index, candidate in enumerate(remaining):
                joined = _join(current, candidate, tolerance_m)
                if joined is not None:
                    current = joined
                    remaining.pop(index)
                    extended = True
                    break
        chains.append(current)

    # By ground length, not vertex count: the first part is the one the trail's stored
    # profile belongs to, and a short, finely digitised spur is not the main walk.
    chains.sort(key=lambda line: -line_length_m(line))
    return chains


def _join(
    line: list[Coordinate], candidate: list[Coordinate], tolerance_m: float
) -> list[Coordinate] | None:
    """Attach ``candidate`` to either end of ``line``, reversing it if that is the fit."""
    if distance_m(line[-1], candidate[0]) <= tolerance_m:
        return line + candidate[1:]
    if distance_m(line[-1], candidate[-1]) <= tolerance_m:
        return line + list(reversed(candidate))[1:]
    if distance_m(line[0], candidate[-1]) <= tolerance_m:
        return candidate + line[1:]
    if distance_m(line[0], candidate[0]) <= tolerance_m:
        return list(reversed(candidate)) + line[1:]
    return None


def derive_trails(
    features: Iterable[dict[str, Any]],
    *,
    place_id: str,
    place_slug: str,
    sample_elevation: ElevationSampler | None = None,
) -> list[DerivedTrail]:
    """Measure every trail in a park's slice of the trails layer."""
    segments = segments_of(features)
    derived: list[DerivedTrail] = []

    for name, group in sorted(group_by_name(segments).items()):
        properties = group[0]["properties"]
        parts = [TrailPart(coordinates=line) for line in chain(group)]
        for part in parts:
            part.measurement = measure.measure(part.coordinates, sample_elevation)

        measurements = [part.measurement for part in parts if part.measurement is not None]
        total_length = sum(item.length_m for item in measurements)
        trail = DerivedTrail(
            id=ids.trail_id(place_slug, name),
            placeID=place_id,
            name=name,
            lengthMetres=total_length,
            parts=parts,
            segmentCount=len(group),
            source={
                "dataset": "nps-public-trails",
                "geometryID": properties.get("GEOMETRYID"),
                "status": properties.get("TRLSTATUS"),
                "use": properties.get("TRLUSE"),
                "surface": properties.get("TRLSURFACE"),
                "trailClass": properties.get("TRLCLASS"),
                "seasonal": properties.get("SEASONAL"),
                "seasonalNotes": properties.get("SEASDESC"),
            },
        )

        with_elevation = [item for item in measurements if item.has_elevation]
        if with_elevation and len(with_elevation) == len(measurements):
            trail.gainMetres = sum(item.elevation_gain_m or 0.0 for item in with_elevation)
            trail.lossMetres = sum(item.elevation_loss_m or 0.0 for item in with_elevation)
            trail.highPointMetres = max(item.high_point_m or 0.0 for item in with_elevation)
            trail.lowPointMetres = min(item.low_point_m or 0.0 for item in with_elevation)
            trail.slopeLengthMetres = sum(item.slope_length_m or 0.0 for item in with_elevation)
            longest = max(range(len(measurements)), key=lambda index: measurements[index].length_m)
            trail.profilePartIndex = longest
            trail.profile = [
                {"distanceMetres": point.distance_m, "elevationMetres": point.elevation_m}
                for point in measurements[longest].profile
            ]
            trail.elevationCoverage = 1.0
        elif measurements:
            covered = sum(item.elevation_coverage * item.length_m for item in measurements)
            trail.elevationCoverage = covered / total_length if total_length else 0.0

        derived.append(trail)

    return derived


def measurement_method() -> dict[str, Any]:
    """The method, written into the pack so a figure can be explained later.

    A length without its method is an opinion. This is what §8 means by "every trail is
    measured the same way", recorded next to the numbers it produced.
    """
    return {
        "lengthBasis": "horizontal (map) length on the WGS84 ellipsoid",
        "stationIntervalMetres": measure.STATION_INTERVAL_M,
        "smoothingWindowMetres": measure.SMOOTHING_WINDOW_M,
        "gainThresholdMetres": measure.HYSTERESIS_THRESHOLD_M,
        "profileSampleCount": measure.PROFILE_SAMPLE_COUNT,
        "elevationSource": "USGS 3DEP, bilinear, fixed ground resolution per park",
        "segmentJoinToleranceMetres": JOIN_TOLERANCE_M,
        "notDerivedYet": ["difficulty", "routeType", "features", "sightIDs", "trailheadID"],
    }
