"""Every state park on the map, from PAD-US (``SPECIFICATION.md`` §5, tier 3).

The curated state parks in ``content/state-parks.json`` carry a written summary and stay
as they are. Everything else PAD-US designates a state park (``Des_Tp = 'SP'``) joins
them with what the source publishes: a name, a designation, a boundary, an area and its
state. That is a state park system's own unit list, so it holds state beaches, historic
parks, natural areas and recreation areas as well as parks by that name.

PAD-US also designates local land 'SP': Buffalo's traffic triangles and medians, town
playgrounds, county and private parcels. A record counts only when a state body manages
it or its own name carries a state designation (``is_state_park_record``), so a
county-run "Scales Lake State Beach" stays and the City of Buffalo's "4Th St" does not.

PAD-US is a compilation, and its unit names show it. A park is often split across
several records ("Bonny Lake State Park" and "Bonny Lake State Park/South Republican
State Wildlife Area"), so records are merged on a cleaned name within a state. Units
PAD-US marks as closed to the public are left out: a pin is an invitation.

PAD-US also files land by state, so a park that reaches a state line can leave a sliver
under its own name in the neighbouring state's file (``fold_slivers``). That sliver is
part of the park beside it, not a second park.
"""

from __future__ import annotations

import json
import math
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

# PAD-US manager names (``Mang_Name``) for a state body: state parks and recreation,
# natural resources, conservation, fish and wildlife, land, other state, state land
# board, and a state record whose agency is not known.
STATE_MANAGERS = frozenset({"SPR", "SDNR", "SDC", "SFW", "SDOL", "OTHS", "SLB", "UNK"})

# What PAD-US writes in ``Loc_Mang`` when it does not know the manager.
NO_MANAGER = frozenset({"", "unknown", "unk"})

# Outline generalisation, as for the other non-park tiers (about 110 m).
TOLERANCE = 0.0011

# A unit is a sliver of a same-named park in another state when it lies within this
# distance of that park...
SLIVER_GAP_M = 1_000.0
# ...and either has no area of its own, or is at most this share of the park's area and
# is managed by the park's manager or by an agency that names the park's state. Twin
# parks across a line (Bear Lake, Pymatuning, White Clay Creek, Mayo River) are each run
# by their own state, so the manager is what tells them apart from a sliver.
SLIVER_SHARE = 0.02

# The names an agency uses for its state ("NJ Department of…", "State of Minnesota").
STATE_NAMES = {
    "AL": "Alabama", "AK": "Alaska", "AZ": "Arizona", "AR": "Arkansas", "CA": "California",
    "CO": "Colorado", "CT": "Connecticut", "DC": "District of Columbia", "DE": "Delaware",
    "FL": "Florida", "GA": "Georgia", "HI": "Hawaii", "ID": "Idaho", "IL": "Illinois",
    "IN": "Indiana", "IA": "Iowa", "KS": "Kansas", "KY": "Kentucky", "LA": "Louisiana",
    "ME": "Maine", "MD": "Maryland", "MA": "Massachusetts", "MI": "Michigan",
    "MN": "Minnesota", "MS": "Mississippi", "MO": "Missouri", "MT": "Montana",
    "NE": "Nebraska", "NV": "Nevada", "NH": "New Hampshire", "NJ": "New Jersey",
    "NM": "New Mexico", "NY": "New York", "NC": "North Carolina", "ND": "North Dakota",
    "OH": "Ohio", "OK": "Oklahoma", "OR": "Oregon", "PA": "Pennsylvania",
    "RI": "Rhode Island", "SC": "South Carolina", "SD": "South Dakota", "TN": "Tennessee",
    "TX": "Texas", "UT": "Utah", "VT": "Vermont", "VA": "Virginia", "WA": "Washington",
    "WV": "West Virginia", "WI": "Wisconsin", "WY": "Wyoming",
}


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
    units = merge(features, curated_patterns)
    slivers = fold_slivers(units, _curated_units(curated, places, boundaries))
    if slivers:
        print(f"    state parks: {len(slivers)} slivers across a state line joined to their park")
    added = 0
    for key, unit in sorted(units.items()):
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
        if not state or not raw or not is_state_park_record(properties):
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
                "manager": _manager(properties.get("Loc_Mang")),
            },
        )
        unit["polygons"].extend(outline.polygons_of(feature.get("geometry")))
        unit["acres"] += float(properties.get("GIS_Acres") or 0)
    return units


def fold_slivers(
    units: dict[str, dict[str, Any]],
    curated: dict[str, dict[str, Any]] | None = None,
) -> dict[str, str]:
    """Join each sliver PAD-US filed across a state line to the park it belongs to.

    A sliver is a unit named as a park in another state, lying within ``SLIVER_GAP_M`` of
    it, that has no area of its own or is a small share of the park's and is run by the
    park's manager or by an agency of the park's state (``_is_sliver``). It is removed from
    ``units``; its outline and acres join the park's when the park is in ``units``, and
    it is simply left out when the park is a curated one (``curated``, keyed by place
    identifier), whose outline is drawn from its own records. The park keeps its states:
    a sliver is not a claim that the park reaches the next state.

    Returns sliver key → the key (or curated identifier) of the park it joined.
    """
    curated = curated or {}
    candidates = {**units, **curated}
    by_name: dict[str, list[str]] = {}
    for key, unit in candidates.items():
        by_name.setdefault(_full_name(unit), []).append(key)

    parent: dict[str, str] = {}
    for key, unit in sorted(units.items()):
        beside = [
            (_gap_m(unit["polygons"], candidates[other]["polygons"]), -candidates[other]["acres"],
             other)
            for other in by_name[_full_name(unit)]
            if other != key and _is_sliver(unit, candidates[other])
        ]
        beside = [entry for entry in beside if entry[0] <= SLIVER_GAP_M]
        if beside:
            parent[key] = min(beside)[2]

    def park_of(key: str) -> str:
        # A sliver of a sliver joins the park at the end of the chain. Each step is to a
        # strictly larger unit, so the chain ends.
        while key in parent:
            key = parent[key]
        return key

    joined: dict[str, str] = {}
    for key in sorted(parent):
        park_key = park_of(key)
        sliver = units.pop(key)
        joined[key] = park_key
        if park_key in units:
            park = units[park_key]
            park["polygons"].extend(sliver["polygons"])
            park["acres"] += sliver["acres"]
    return joined


def _full_name(unit: dict[str, Any]) -> str:
    return f"{unit['name']} {unit['designation']}".casefold()


def _is_sliver(unit: dict[str, Any], park: dict[str, Any]) -> bool:
    """Whether ``unit`` could be a sliver of ``park`` by state, area and manager; distance is
    checked by the caller, as it is the costly test."""
    states = park.get("states") or [park["state"]]
    if unit["state"] in states or park["acres"] <= unit["acres"]:
        return False
    if unit["acres"] < 1:
        return True
    if unit["acres"] > SLIVER_SHARE * park["acres"]:
        return False
    manager = (unit.get("manager") or "").strip()
    park_manager = (park.get("manager") or "").strip()
    if manager.casefold() not in ("", "unknown") and manager.casefold() == park_manager.casefold():
        return True
    return any(_names_state(manager, state) for state in states)


def _names_state(manager: str, state: str) -> bool:
    """Whether an agency's name names a state: "NJ Department of…", "New York State"."""
    if not manager:
        return False
    if re.search(rf"\b{re.escape(state)}\b", manager):
        return True
    name = STATE_NAMES.get(state)
    if not name:
        return False
    # "Virginia" inside "West Virginia" names the other state.
    guard = r"(?<!West )" if state == "VA" else ""
    return re.search(rf"{guard}\b{re.escape(name)}\b", manager, re.IGNORECASE) is not None


def _gap_m(first: list[outline.Polygon], second: list[outline.Polygon]) -> float:
    """The ground distance between two outlines in metres, 0 where they touch or overlap,
    infinite where either is empty. Flat-Earth, which is plenty within a kilometre."""
    box_a, box_b = outline.bbox(first), outline.bbox(second)
    if box_a is None or box_b is None:
        return math.inf
    latitude = (box_a[0] + box_a[2]) / 2
    metres_x = 111_320.0 * math.cos(math.radians(latitude))
    metres_y = 110_574.0
    # Boxes further apart than the gap that matters need no closer look.
    margin_lat = SLIVER_GAP_M / metres_y
    margin_lon = SLIVER_GAP_M / max(metres_x, 1.0)
    if box_a[0] > box_b[2] + margin_lat or box_b[0] > box_a[2] + margin_lat:
        return math.inf
    if box_a[1] > box_b[3] + margin_lon or box_b[1] > box_a[3] + margin_lon:
        return math.inf
    for one, other in ((first, second), (second, first)):
        if any(outline.contains(other, *polygon[0][0]) for polygon in one if polygon[0]):
            return 0.0

    def projected(polygons: list[outline.Polygon]) -> list[list[tuple[float, float]]]:
        return [
            [(lon * metres_x, lat * metres_y) for lon, lat in ring]
            for polygon in polygons
            for ring in polygon
        ]

    rings_a, rings_b = projected(first), projected(second)
    best = math.inf
    for points, rings in ((rings_a, rings_b), (rings_b, rings_a)):
        for point in (point for ring in points for point in ring):
            for ring in rings:
                for start, end in zip(ring, ring[1:] + ring[:1], strict=True):
                    best = min(best, _segment_distance(point, start, end))
    return best


def _segment_distance(
    point: tuple[float, float], start: tuple[float, float], end: tuple[float, float]
) -> float:
    (px, py), (ax, ay), (bx, by) = point, start, end
    dx, dy = bx - ax, by - ay
    if dx == 0 and dy == 0:
        return math.hypot(px - ax, py - ay)
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def _curated_units(
    curated: list[dict[str, Any]],
    places: list[dict[str, Any]],
    boundaries: dict[str, Any],
) -> dict[str, dict[str, Any]]:
    """The curated state parks already among ``places``, shaped as census units so a
    sliver beside one can be recognised (``fold_slivers``)."""
    by_id = {place["id"]: place for place in places}
    units: dict[str, dict[str, Any]] = {}
    for site in curated:
        place = by_id.get(site["id"])
        entry = boundaries.get(site["id"])
        if site.get("kind") != "statePark" or place is None or not entry:
            continue
        units[site["id"]] = {
            "name": site["name"],
            "designation": site["designation"],
            "states": list(site.get("states") or []),
            "polygons": [
                [outline.decode(ring) for ring in polygon] for polygon in entry["polygons"]
            ],
            "acres": float((place.get("facts") or {}).get("areaAcres") or 0),
            "manager": place.get("managedBy"),
        }
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


def is_state_park_record(properties: dict[str, Any]) -> bool:
    """Whether a PAD-US record is state park land: a state body manages it, or its own
    name carries a state designation (a TVA parcel of a Tennessee state park, a
    county-run state beach). Asked of each record before any merging, so a private parcel
    named for the park it lies in still joins that park."""
    if (properties.get("Mang_Name") or "").strip().upper() in STATE_MANAGERS:
        return True
    raw = (properties.get("Unit_Nm") or properties.get("Loc_Nm") or "").strip()
    return any(_designation_of(part) for part in re.split(r"\s*/\s*", raw) if part.strip())


def _manager(text: str | None) -> str | None:
    """The managing agency as PAD-US names it, or None where it says it does not know."""
    manager = (text or "").strip()
    return None if manager.casefold() in NO_MANAGER else manager


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
