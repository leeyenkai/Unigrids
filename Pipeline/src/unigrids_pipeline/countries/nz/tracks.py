"""New Zealand's trails from DOC's own track layer, as routes the shared catalogue measures.

DOC Tracks (``DOC_Tracks_Open_Data``) is DOC's asset register of the tracks it maintains:
one record per asset, each with DOC's site code (``FlocID``, ``MILFRDTK-TK03``), a name,
the walking category its website shows and whether it is open and in public use. Most
records are whole tracks ("Marokopa Falls Tk"); a long track is several records, one per
section, named "<track> - <from> To <to>" ("Milford Tk - Clinton Hut Jcn To Bus Stop").

A trail here is a record, or the sections of one site that name the same track before their
dash, joined. Its name is DOC's, with the asset prefix off and "Tk" spelled out; nothing
else is rewritten. Records that are closed, not in public use, or not walks (cycle tracks,
pavement) are left out. The category travels with the trail when every section agrees on
one, as Norway's Turrutebasen grade does; sections that disagree leave it unsaid.

The category is the trail's published grade (``TrailGrade.System.newZealandTrackCategory``
in the app), shown as DOC writes it and read into the catalogue's bands.
"""

from __future__ import annotations

import json
from functools import cache
from pathlib import Path
from typing import Any

from ... import outline, rawstore
from ..abroad import trails as abroad_trails
from . import rules

Record = dict[str, Any]

SOURCE = "nz-doc-tracks"
FILE = "tracks.geojson"
LINE_SOURCE = "doc"
GRADE_KEY = "publishedGrade"
"""Where a trail's DOC category is written."""


def latest_path() -> Path | None:
    directory = rawstore.latest(SOURCE, FILE)
    return directory / FILE if directory else None


def read_features(path: Path | None = None) -> list[Record] | None:
    """Every track record fetched, or None if the layer was never fetched."""
    path = path or latest_path()
    if path is None:
        return None
    # Read once per saved version: the catalogue asks once a park.
    return _read(path, path.stat().st_mtime_ns)


@cache
def _read(path: Path, _version: int) -> list[Record]:
    return json.loads(path.read_text()).get("features") or []


def is_walk(properties: Record) -> bool:
    """An open track in public use that is walked: not a cycle track or pavement."""
    asset_class = (properties.get("SubObjectType") or "").strip().lower()
    return rules.is_open_to_the_public(properties) and bool(asset_class) and (
        asset_class not in rules.NOT_WALKS
    )


def routes(
    park: Record, features: list[Record] | None, polygons: list[outline.Polygon]
) -> list[abroad_trails.Route]:
    """The park's DOC tracks: records kept where they lie in the park, sections of one
    track joined by their site and the name before their dash."""
    if not features:
        return []
    box = outline.bbox(polygons)
    kept: list[tuple[Record, list[list[tuple[float, float]]]]] = []
    for feature in features:
        properties = feature.get("properties") or {}
        if not is_walk(properties) or not rules.track_name(properties.get("TechObjectName")):
            continue
        lines = [
            line
            for line in abroad_trails._lines(feature.get("geometry") or {})
            if abroad_trails._inside(polygons, box, line)
        ]
        if lines:
            kept.append((properties, lines))
    # A base name two sections of one site share is a track; one only one record carries
    # is part of that record's own name ("Te Araroa - Puhoi Track" alone is that track).
    bases: dict[tuple[str, str], int] = {}
    for properties, _ in kept:
        name = rules.track_name(properties.get("TechObjectName"))
        if base := rules.track_base(name):
            key = (rules.site_of(properties.get("FlocID")), rules.normal(base))
            bases[key] = bases.get(key, 0) + 1
    groups: dict[str, dict[str, Any]] = {}
    for properties, lines in kept:
        name = rules.track_name(properties.get("TechObjectName"))
        site = rules.site_of(properties.get("FlocID"))
        base = rules.track_base(name)
        if base and bases.get((site, rules.normal(base)), 0) >= 2:
            key, title = f"doc:{site}/{rules.normal(base)}", base
        else:
            local = properties.get("FlocID") or properties.get("GlobalID")
            key, title = f"doc:{local}", rules.without_generic_prefix(name)
        group = groups.setdefault(key, {"names": {}, "records": [], "segments": []})
        group["names"][title] = group["names"].get(title, 0) + 1
        group["records"].append(properties)
        group["segments"].extend(lines)
    found: list[abroad_trails.Route] = []
    for key, group in groups.items():
        name = max(group["names"], key=lambda title: (group["names"][title], -len(title)))
        extra: Record = {}
        if category := agreed_category(group["records"]):
            extra[GRADE_KEY] = rules.track_grade(category)
        dogs = rules.dogs_allowed([
            rules.characteristic(record, "WEB_DOGS_ALLOWED") for record in group["records"]
        ])
        if dogs is not None:
            extra["dogsAllowed"] = dogs
        found.append(abroad_trails.Route(
            key=key,
            name=name,
            latin_name=name,
            source=LINE_SOURCE,
            segments=group["segments"],
            names=(name,),
            extra=extra,
        ))
    return sorted(found, key=lambda route: (route.name, route.key))


def agreed_category(records: list[Record]) -> str | None:
    """The DOC category every record of a track carries, or None where they differ or
    one carries none."""
    categories = {
        rules.track_category(
            rules.characteristic(record, "WEB_CATEGORY_TRACK"), record.get("SubObjectType")
        )
        for record in records
    }
    if len(categories) != 1:
        return None
    return categories.pop()
