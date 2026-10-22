"""Every state park on the map, from PAD-US (``SPECIFICATION.md`` §5, tier 3).

The curated state parks in ``content/state-parks.json`` carry a written summary and stay
as they are. Everything else PAD-US designates a state park (``Des_Tp = 'SP'``) joins
them with what the source publishes: a name, a designation, a boundary, an area and its
state. That is a state park system's own unit list, so it holds state beaches, historic
parks, natural areas and recreation areas as well as parks by that name.

PAD-US is a compilation, and its unit names show it. A park is often split across
several records ("Bonny Lake State Park" and "Bonny Lake State Park/South Republican
State Wildlife Area"), so records are merged on a cleaned name within a state. Units
PAD-US marks as closed to the public are left out: a pin is an invitation.
"""

from __future__ import annotations

import json
import re
from collections.abc import Iterable
from pathlib import Path
from typing import Any

from . import ids, outline, rawstore
from .rawstore import FetchRecord, SourceTerms
from .sources import arcgis, http

LAYER = (
    "https://services.arcgis.com/v01gqwM5QqNysAAi/ArcGIS/rest/services/Fee_Manager/"
    "FeatureServer/0"
)
FIELDS = "Unit_Nm,Loc_Nm,Mang_Name,Loc_Mang,Des_Tp,State_Nm,GIS_Acres,Pub_Access"
FILE = "state-parks.geojson"

TERMS = SourceTerms(
    identifier="padus-state-parks",
    title="PAD-US fee-manager layer, every unit designated a state park",
    url=LAYER,
    licence="USGS data release, public domain",
    attribution="Boundaries: USGS Gap Analysis Project, PAD-US",
    notes="Des_Tp = 'SP', state by state, generalised by the server to about 50 m.",
)

# Every state and territory PAD-US files land under.
STATES = (
    "AK", "AL", "AR", "AS", "AZ", "CA", "CO", "CT", "DC", "DE", "FL", "GA", "GU", "HI",
    "IA", "ID", "IL", "IN", "KS", "KY", "LA", "MA", "MD", "ME", "MI", "MN", "MO", "MP",
    "MS", "MT", "NC", "ND", "NE", "NH", "NJ", "NM", "NV", "NY", "OH", "OK", "OR", "PA",
    "PR", "RI", "SC", "SD", "TN", "TX", "UT", "VA", "VI", "VT", "WA", "WI", "WV", "WY",
)

# What a state park unit's name can end in, longest first so "State Historic Park" is
# not read as "Park". A name with none of these is a state park by its designation code.
DESIGNATIONS = (
    "State Vehicular Recreation Area",
    "State Underwater Park",
    "State Historical Park",
    "State Historic Park",
    "State Historic Site",
    "State Historic District",
    "State Natural Reserve",
    "State Natural Area",
    "State Recreation Area",
    "State Recreational Area",
    "State Scenic Area",
    "State Scenic Reserve",
    "State Park Reserve",
    "State Marine Park",
    "State Wayside Park",
    "State Seashore",
    "State Reserve",
    "State Beach",
    "State Trail",
    "State Park",
)

# Units PAD-US marks closed to the public (``XA``).
CLOSED = "XA"

# Outline generalisation, as for the other non-park tiers (about 110 m).
TOLERANCE = 0.0011


def fetch(version: str) -> Path:
    """Every state park unit, state by state, into ``raw/<version>/padus/``."""
    directory = rawstore.version_directory("padus", version)
    record = FetchRecord(source=TERMS, fetched_at=rawstore.utc_now())
    features: list[dict[str, Any]] = []
    with http.client() as session:
        for state in STATES:
            found = arcgis.query_features(
                session,
                LAYER,
                where=f"Des_Tp = 'SP' AND State_Nm = '{state}'",
                out_fields=FIELDS,
                record=record,
                max_allowable_offset=0.0005,
                page_size=200,
            )
            features.extend(found)
            print(f"    state parks: {state} {len(found)}", flush=True)
    path = directory / FILE
    path.write_text(json.dumps({"type": "FeatureCollection", "features": features}))
    record.add_file(path, root=directory)
    record.write(directory)
    print(f"    state parks: {len(features)} PAD-US records")
    return directory


def build(
    raw_padus: Path,
    places: list[dict[str, Any]],
    boundaries: dict[str, Any],
    registry: ids.Registry,
    curated: list[dict[str, Any]],
) -> int:
    """Append every state park not already curated to ``places``; return how many."""
    path = raw_padus / FILE
    if not path.exists():
        print("    state parks: no PAD-US census in the raw store, only the curated set")
        return 0
    features = json.loads(path.read_text()).get("features") or []
    taken = {place["id"] for place in places}
    curated_patterns = _curated_patterns(curated)
    added = 0
    for key, unit in sorted(merge(features, curated_patterns).items()):
        place, entry = _place(unit)
        identifier = registry.resolve(key, place["id"], qualifier=unit["state"])
        if identifier in taken:
            continue
        place["id"] = identifier
        taken.add(identifier)
        places.append(place)
        if entry:
            boundaries[identifier] = entry
        added += 1
    print(f"    state parks: {added} from PAD-US beside {len(curated)} curated sites")
    return added


def merge(
    features: Iterable[dict[str, Any]],
    curated_patterns: dict[str, list[re.Pattern[str]]] | None = None,
) -> dict[str, dict[str, Any]]:
    """PAD-US records grouped into parks, keyed ``padus-sp:<state>:<full name>``."""
    curated_patterns = curated_patterns or {}
    units: dict[str, dict[str, Any]] = {}
    for feature in features:
        properties = feature.get("properties") or {}
        if (properties.get("Pub_Access") or "").upper() == CLOSED:
            continue
        state = (properties.get("State_Nm") or "").strip().upper()
        raw = (properties.get("Unit_Nm") or properties.get("Loc_Nm") or "").strip()
        if not state or not raw:
            continue
        if any(p.fullmatch(raw) for p in curated_patterns.get(state, [])):
            continue
        name, designation = clean_name(raw)
        if not name:
            continue
        full = f"{name} {designation}"
        key = f"padus-sp:{state}:{full}"
        unit = units.setdefault(
            key,
            {
                "name": name,
                "designation": designation,
                "state": state,
                "polygons": [],
                "acres": 0.0,
                "manager": (properties.get("Loc_Mang") or "").strip() or None,
            },
        )
        unit["polygons"].extend(outline.polygons_of(feature.get("geometry")))
        unit["acres"] += float(properties.get("GIS_Acres") or 0)
    return units


def clean_name(raw: str) -> tuple[str, str]:
    """``("Bonny Lake", "State Park")`` from PAD-US's unit name.

    A compound name — two units' names joined with a slash — keeps the part that names a
    state park. Capitals are title-cased; a name that carries no designation is a state
    park by the code that put it in this set.
    """
    parts = [part.strip() for part in re.split(r"\s*/\s*", raw) if part.strip()]
    chosen = next((part for part in parts if _designation_of(part)), parts[0] if parts else "")
    if chosen.isupper():
        from .lands_build import title_case

        chosen = title_case(chosen)
    chosen = re.sub(r"\s+", " ", chosen).strip(" -,")
    designation = _designation_of(chosen)
    if designation:
        name = chosen[: -len(designation)].strip(" -,")
        return name, designation
    return chosen, "State Park"


def _designation_of(text: str) -> str | None:
    lowered = text.lower()
    for designation in DESIGNATIONS:
        if lowered.endswith(designation.lower()):
            # Keep the source's own capitalisation of the words, normalised to title case.
            return designation
    return None


def proposed_id(name: str, designation: str, state: str) -> str:
    """``sp-co-cheyenne-mountain``; ``sp-ca-refugio-state-beach`` for anything that is not
    simply a state park, so a park and a beach of one name never contend."""
    stem = name if designation == "State Park" else f"{name} {designation}"
    return f"sp-{state.lower()}-{ids.slug(stem)}"


def _place(unit: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any] | None]:
    from .lands_build import lower_small_words

    polygons = unit["polygons"]
    simplified = outline.generalise(polygons, TOLERANCE)
    box = outline.bbox(simplified)
    entry = None
    if simplified and box is not None:
        entry = {
            "bbox": [round(value, 5) for value in box],
            "polygons": [[outline.encode(ring) for ring in polygon] for polygon in simplified],
        }
        latitude, longitude = outline.label_point(simplified) or (0.0, 0.0)
    else:
        # Too small to survive generalisation: a pin at the middle of what PAD-US drew.
        rings = [ring for polygon in polygons for ring in polygon[:1]]
        points = [point for ring in rings for point in ring]
        if not points:
            latitude = longitude = 0.0
        else:
            longitude = sum(p[0] for p in points) / len(points)
            latitude = sum(p[1] for p in points) / len(points)
    place: dict[str, Any] = {
        "id": proposed_id(unit["name"], unit["designation"], unit["state"]),
        # Tidied for display only: the registry key keeps the name as PAD-US spelled it,
        # so an identifier never changes because a capital did.
        "name": lower_small_words(unit["name"]),
        "designation": unit["designation"],
        "kind": "statePark",
        "agency": "stateAgency",
        "states": [unit["state"]],
        "centre": {"latitude": round(latitude, 5), "longitude": round(longitude, 5)},
        "themes": [],
        "facts": {"areaAcres": round(unit["acres"])} if unit["acres"] >= 1 else {},
    }
    if entry:
        south, west, north, east = entry["bbox"]
        place["extent"] = {"south": south, "west": west, "north": north, "east": east}
    if unit.get("manager"):
        place["managedBy"] = unit["manager"]
    return place, entry


def _curated_patterns(curated: list[dict[str, Any]]) -> dict[str, list[re.Pattern[str]]]:
    """The PAD-US names each curated state park is assembled from, as patterns by state.

    The curated file writes them as SQL ``LIKE`` patterns, because that is how they are
    fetched; here they keep those records out of the census so a park is not drawn twice.
    """
    patterns: dict[str, list[re.Pattern[str]]] = {}
    for site in curated:
        if site.get("kind") != "statePark":
            continue
        for like in site.get("padus") or []:
            regex = "".join(
                ".*" if char == "%" else "." if char == "_" else re.escape(char) for char in like
            )
            for state in site.get("states") or []:
                patterns.setdefault(state, []).append(re.compile(regex, re.IGNORECASE))
    return patterns
