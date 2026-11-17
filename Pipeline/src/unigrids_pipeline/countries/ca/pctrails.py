"""Canada's trails from Parks Canada's own layer, as routes the shared catalogue measures.

Parks Canada publishes the trails it is responsible for — in national parks, historic
sites and marine conservation areas — as one line layer (open.canada.ca, "Trails APCA",
OGL–Canada). The layer has no park field and no trail identifier: a record is a stretch of
line with the trail's official name, its summer and winter difficulty, and one activity
(``General_Activity``), so a line hikers and riders share is in the layer twice, once for
each. A trail here is the hiking records of one name inside a park, their lines joined
where they lie together (two trails called "Lakeshore" at opposite ends of a park stay
two), each stretch kept once however many activities repeat it.

The rating travels with the trail when every hiking record of it agrees on one, as
Norway's grade and DOC's category do; records that disagree leave it unsaid. It is the
trail's published grade (``TrailGrade.System.parksCanadaDifficulty`` in the app), shown as
Parks Canada writes it and read into the catalogue's bands.

The registry key is the park and the name, ``parkscanada:<park>/<name>``, and a second
stretch of the same name its rounded position too: the layer gives nothing steadier.
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

SOURCE = "ca-pc-trails"
FILE = "trails.geojson"
LINE_SOURCE = "parksCanada"
GRADE_KEY = "publishedGrade"


def latest_path() -> Path | None:
    directory = rawstore.latest(SOURCE, FILE)
    return directory / FILE if directory else None


def read_features(path: Path | None = None) -> list[Record] | None:
    """Every trail record fetched, or None if the layer was never fetched."""
    path = path or latest_path()
    if path is None:
        return None
    return _read(path, path.stat().st_mtime_ns)


@cache
def _read(path: Path, _version: int) -> list[Record]:
    return json.loads(path.read_text()).get("features") or []


def _signature(line: list[tuple[float, float]]) -> tuple[tuple[float, float], ...]:
    """A stretch's vertices to about a metre, either way round: the same line repeated for
    another activity is the same stretch."""
    rounded = tuple((round(x, 5), round(y, 5)) for x, y in line)
    return min(rounded, rounded[::-1])


def routes(
    park: Record, features: list[Record] | None, polygons: list[outline.Polygon]
) -> list[abroad_trails.Route]:
    """The park's Parks Canada trails: named hiking records whose lines lie in the park,
    joined by name and closeness."""
    if not features:
        return []
    box = outline.bbox(polygons)
    # Every activity a stretch carries, wherever the hiking record of it is.
    activities: dict[tuple[tuple[float, float], ...], set[int]] = {}
    hiking: dict[str, list[tuple[Record, list[tuple[float, float]]]]] = {}
    for feature in features:
        properties = feature.get("properties") or {}
        name = rules.trail_name(properties.get("Name_Official_e"))
        if not name or properties.get("Section_Type") in rules.NOT_WALKED:
            continue
        lines = [
            line
            for line in abroad_trails._lines(feature.get("geometry") or {})
            if abroad_trails._inside(polygons, box, line)
        ]
        for line in lines:
            activity = properties.get("General_Activity")
            activities.setdefault(_signature(line), set()).add(
                int(activity) if isinstance(activity, int | float) else 0
            )
            if activity == rules.HIKING:
                hiking.setdefault(name, []).append((properties, line))
    slug = abroad_trails.park_slug(park["id"])
    found: list[abroad_trails.Route] = []
    for name, records in sorted(hiking.items()):
        unique: dict[tuple[tuple[float, float], ...], tuple[Record, list[tuple[float, float]]]] = {}
        for properties, line in records:
            unique.setdefault(_signature(line), (properties, line))
        stretches = [
            {"id": index, "line": line, "properties": properties}
            for index, (properties, line) in enumerate(unique.values())
        ]
        clusters = abroad_trails._clusters(stretches)
        clusters.sort(key=lambda cluster: _first_point(cluster))
        for number, cluster in enumerate(clusters):
            key = f"parkscanada:{slug}/{ids.slug(name)}"
            if number:
                latitude, longitude = _centre(cluster)
                key += f"@{latitude:.2f},{longitude:.2f}"
            extra: Record = {}
            if grade := agreed_difficulty([stretch["properties"] for stretch in cluster]):
                extra[GRADE_KEY] = rules.trail_grade(grade)
            uses = ["Hike"]
            shared = set().union(*(activities.get(_signature(s["line"]), set()) for s in cluster))
            for code, label in rules.ACTIVITY_USES.items():
                if code in shared:
                    uses.append(label)
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


def _first_point(cluster: list[Record]) -> tuple[float, float]:
    return min((stretch["line"][0][1], stretch["line"][0][0]) for stretch in cluster)


def _centre(cluster: list[Record]) -> tuple[float, float]:
    points = [point for stretch in cluster for point in stretch["line"]]
    return (
        sum(point[1] for point in points) / len(points),
        sum(point[0] for point in points) / len(points),
    )


def agreed_difficulty(records: list[Record]) -> str | None:
    """The summer rating every hiking record of a trail carries, or None where they differ
    or one carries none."""
    grades = {rules.difficulty(record.get("Summer_Classification_Été")) for record in records}
    if len(grades) != 1:
        return None
    return grades.pop()


def lines_in(features: list[Record], polygons: list[outline.Polygon]) -> int:
    """How many named hiking records lie in an outline: whether a park has trails here."""
    box = outline.bbox(polygons)
    count = 0
    for feature in features:
        properties = feature.get("properties") or {}
        if properties.get("General_Activity") != rules.HIKING:
            continue
        if not rules.trail_name(properties.get("Name_Official_e")):
            continue
        if any(abroad_trails._inside(polygons, box, line)
               for line in abroad_trails._lines(feature.get("geometry") or {})):
            count += 1
    return count
