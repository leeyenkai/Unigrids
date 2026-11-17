"""Queensland's walking tracks from QPWS's own access data, as routes the shared catalogue
measures.

The Queensland Parks and Wildlife Service publishes its estate's roads, tracks and trails
as one dataset ("Queensland Parks and Wildlife Service access", CC BY 4.0), served by
QSpatial's ``ParksTerrestrialProtectedAreas`` map service; its "Walking track" layer is
read whole by the Australian fetch. A record is a stretch of line with the track's name,
its status, its class of construction and its pedestrian class ("Track class 3 to AS
2156.1"), the standard the Australian Walking Track Grading System's five grades are
built on. A trail here is the open, named walking records of one name inside a park,
their lines joined where they lie together (two tracks called "Circuit" at opposite ends
of a park stay two).

The grade travels with the trail when every classed record of it agrees on one, as
Norway's grade and DOC's category do; records that disagree, or a trail none of whose
records is classed, leave it unsaid. It is the
trail's published grade (``TrailGrade.System.australianWalkingTrackGrade`` proposed for
the app), shown as published and read into the catalogue's bands.

The other states publish no open track grades a fetch can read without a key (NSW's NPWS
walking tracks need a token), so their parks' trails come from OpenStreetMap alone.

The registry key is the park and the name, ``qpws:<park>/<name>``, and a second stretch of
the same name its rounded position too: the layer gives nothing steadier.
"""

from __future__ import annotations

import json
from functools import cache
from pathlib import Path
from typing import Any

from ... import ids, outline, rawstore
from ..abroad import trails as abroad_trails
from . import rules

Record = dict[str, Any]

SOURCE = "au-qpws-tracks"
FILE = "tracks.geojson"
LINE_SOURCE = "qpws"
GRADE_KEY = "publishedGrade"
STATE = "AU-QLD"


def latest_path() -> Path | None:
    directory = rawstore.latest(SOURCE, FILE)
    return directory / FILE if directory else None


def read_features(path: Path | None = None) -> list[Record] | None:
    """Every track record fetched, or None if the layer was never fetched."""
    path = path or latest_path()
    if path is None:
        return None
    return _read(path, path.stat().st_mtime_ns)


@cache
def _read(path: Path, _version: int) -> list[Record]:
    return json.loads(path.read_text()).get("features") or []


def routes(
    park: Record, features: list[Record] | None, polygons: list[outline.Polygon]
) -> list[abroad_trails.Route]:
    """The park's QPWS tracks: open, named walking records whose lines lie in the park,
    joined by name and closeness. A park outside Queensland has none here."""
    if not features or park.get("state") != STATE:
        return []
    box = outline.bbox(polygons)
    named: dict[str, list[tuple[Record, list[tuple[float, float]]]]] = {}
    for feature in features:
        properties = feature.get("properties") or {}
        name = rules.track_name(properties.get("name"))
        if not name or not rules.is_open_walking_track(properties):
            continue
        for line in abroad_trails._lines(feature.get("geometry") or {}):
            if abroad_trails._inside(polygons, box, line):
                named.setdefault(name, []).append((properties, line))
    slug = abroad_trails.park_slug(park["id"])
    found: list[abroad_trails.Route] = []
    for name, records in sorted(named.items()):
        stretches = [
            {"id": index, "line": line, "properties": properties}
            for index, (properties, line) in enumerate(records)
        ]
        clusters = abroad_trails._clusters(stretches)
        clusters.sort(key=_first_point)
        for number, cluster in enumerate(clusters):
            key = f"qpws:{slug}/{ids.slug(name)}"
            if number:
                latitude, longitude = _centre(cluster)
                key += f"@{latitude:.2f},{longitude:.2f}"
            extra: Record = {}
            if grade := agreed_grade([stretch["properties"] for stretch in cluster]):
                extra[GRADE_KEY] = rules.published_grade(grade)
            uses = ["Hike"]
            if any(_allowed(stretch["properties"].get("mtb")) for stretch in cluster):
                uses.append("Bicycle")
            if any(_allowed(stretch["properties"].get("horse")) for stretch in cluster):
                uses.append("Horse")
            found.append(abroad_trails.Route(
                key=key,
                name=name,
                latin_name=name,
                source=LINE_SOURCE,
                segments=[stretch["line"] for stretch in cluster],
                uses=", ".join(uses),
                names=(name,),
                extra=extra,
            ))
    return sorted(found, key=lambda route: (route.name, route.key))


def _allowed(value: Any) -> bool:
    """QPWS writes "Yes", "No" or "Unclassified" for whether a use is allowed."""
    return str(value or "").strip().lower() == "yes"


def _first_point(cluster: list[Record]) -> tuple[float, float]:
    return min((stretch["line"][0][1], stretch["line"][0][0]) for stretch in cluster)


def _centre(cluster: list[Record]) -> tuple[float, float]:
    points = [point for stretch in cluster for point in stretch["line"]]
    return (
        sum(point[1] for point in points) / len(points),
        sum(point[0] for point in points) / len(points),
    )


def agreed_grade(records: list[Record]) -> str | None:
    """The track class every classed record of a trail carries, or None where they differ
    or none carries one. A bridge or a flight of steps QPWS leaves "Unclassified" does not
    unsay the class of the track it is on."""
    grades = {grade for record in records if (grade := rules.track_grade(record.get("ped")))}
    if len(grades) != 1:
        return None
    return grades.pop()
