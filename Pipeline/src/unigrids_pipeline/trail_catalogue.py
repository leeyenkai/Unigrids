"""The trail catalogue for every national park (``SPECIFICATION.md`` §8).

The offline pack for Zion measures its trails on a downloaded 10 m elevation grid. Doing
that for sixty-three parks would mean fetching gigabytes of rasters for a few thousand
kilometres of line, so the catalogue the app bundles is measured differently, and the
method is written down for that reason:

1. **Fetch** each park's segments from NPS Public Trails, by unit code, into the raw store.
2. **Join** segments into named trails exactly as the pack does (``trails.chain``), and
   keep the trails whose line lies inside the park's own outline.
3. **Sample** elevation at a station every :data:`STATION_INTERVAL_M` along each trail from
   the USGS 3DEP image service's point sampler, cached in the raw store so a rebuild never
   asks twice.
4. **Measure** with the same smoothing and dead band as the pack (``measure.measure``),
   scaled to the wider station spacing.
5. **Match** each trail to the guide's sights it passes within :data:`SIGHT_REACH_M` of.

Nothing here rates difficulty or says whether a trail is walked out and back: a loop is
recorded where the line closes on itself, and the app estimates difficulty from the
measured length and climb by a published rule, labelled as an estimate.
"""

from __future__ import annotations

import json
import math
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any

import httpx

from . import ids, measure, outline, rawstore, reference_content, trails
from .geo import Coordinate, distance_m
from .rawstore import FetchRecord, SourceTerms
from .sources import arcgis, http

STATION_INTERVAL_M = 30.0
"""Station spacing for the catalogue: three postings of the 10 m model. Coarser than the
pack's 10 m, which is what makes sampling every park's trails from a web service
practical; switchbacks tighter than this lose a little climb, and the stated method says
so."""

SMOOTHING_WINDOW_M = 90.0
"""The moving average, three stations wide, as the pack's is five of its narrower ones."""

PROFILE_POINTS = 60
"""Points kept in each stored profile: enough for a chart across a phone."""

MIN_LENGTH_M = 250.0
"""Shorter named lines are connectors and access paths, not trails anyone picks."""

LINE_TOLERANCE_DEGREES = 0.00007
"""How far a trail's drawn line is generalised: about 7 m, under the layer's own accuracy."""

SIGHT_REACH_M = 200.0
"""A sight counts as on a trail when the trail passes this close to it."""

BOUNDARY_BUFFER_DEGREES = 0.02
"""How far outside the outline a trail may run and still be the park's — a trailhead in
the gateway town, a path that crosses the line and back."""

SAMPLES_PER_REQUEST = 1000
SAMPLE_WORKERS = 4
ELEVATION_SAMPLES = (
    "https://elevation.nationalmap.gov/arcgis/rest/services/3DEPElevation/ImageServer/getSamples"
)

TRAIL_TERMS = SourceTerms(
    identifier="nps-public-trails-national",
    title="NPS Public Trails, every national park",
    url=arcgis.TRAILS_LAYER,
    licence="Public NPS dataset",
    attribution="Trails: National Park Service, NPS Public Trails",
    notes="Fetched by unit code for each of the 63 national parks.",
)

# Parks whose own GIS staff publish no trails in the NPS layer, filled from OpenStreetMap
# instead (``SPECIFICATION.md`` §8 allows it, under the ODbL). Sequoia and Kings Canyon
# only: the Arctic parks that also publish none are trailless wilderness, and right to.
OSM_TRAIL_UNITS = ("SEKI",)
OSM_TRAIL_KINDS = "path|footway|bridleway"

OSM_TRAIL_TERMS = SourceTerms(
    identifier="openstreetmap-trails",
    title="OpenStreetMap named footpaths, via the Overpass API",
    url="https://www.openstreetmap.org/copyright",
    licence="Open Database License (ODbL) 1.0",
    attribution="Trails in Sequoia and Kings Canyon: © OpenStreetMap contributors (ODbL)",
    notes=(
        "Shipped as data, so the trails taken from it are a Derivative Database under the "
        "ODbL: attributed in the app, and available under the same licence."
    ),
)

ELEVATION_TERMS = SourceTerms(
    identifier="usgs-3dep-samples",
    title="USGS 3DEP elevation, sampled along every catalogue trail",
    url=ELEVATION_SAMPLES,
    licence="Public domain (US Geological Survey)",
    attribution="Elevation data courtesy of the U.S. Geological Survey (3DEP)",
    notes=f"Bilinear samples at a station every {STATION_INTERVAL_M:g} m.",
)


# MARK: - Fetch


def fetch(version: str, *, refresh: bool = False) -> Path:
    """Every national park's trail segments, one file per park."""
    directory = rawstore.version_directory("trails-national", version)
    record = FetchRecord(source=TRAIL_TERMS, fetched_at=rawstore.utc_now())
    with http.client() as session:
        for code in _unit_codes():
            path = directory / f"{code}.geojson"
            if path.exists() and not refresh:
                continue
            features = arcgis.trails_for_unit(session, code, record=record)
            path.write_text(json.dumps({"type": "FeatureCollection", "features": features}))
            record.add_file(path, root=directory)
            print(f"    trails-national/{code}: {len(features)} segments", flush=True)
    record.write(directory)
    return directory


def _unit_codes() -> list[str]:
    codes: set[str] = set()
    for _, row in reference_content.national_park_rows():
        codes.add(row["npsParkCode"].upper())
        codes.add(reference_content.api_code(row).upper())
    return sorted(codes)


def fetch_osm(version: str, unit_outlines: dict[str, list[outline.Polygon]]) -> None:
    """Named footpaths from OpenStreetMap for the parks in :data:`OSM_TRAIL_UNITS`, as
    NPS-shaped features in ``trails-national/<code>-osm.geojson``."""
    from .geo import BoundingBox
    from .sources import osm

    directory = rawstore.version_directory("trails-national", version)
    record = FetchRecord(source=OSM_TRAIL_TERMS, fetched_at=rawstore.utc_now())
    with http.client() as session:
        for unit in OSM_TRAIL_UNITS:
            path = directory / f"{unit}-osm.geojson"
            if path.exists():
                continue
            polygons = [
                polygon
                for _, row in reference_content.national_park_rows()
                if reference_content.api_code(row).upper() == unit
                for polygon in unit_outlines.get(row["npsParkCode"].upper(), [])
            ]
            box = outline.bbox(polygons)
            if box is None:
                print(f"    trails-national/{unit}-osm: no outline to search within")
                continue
            south, west, north, east = box
            query = osm.trail_query(
                BoundingBox(south=south, west=west, north=north, east=east), OSM_TRAIL_KINDS
            )
            payload = osm.download_query(session, query, record=record)
            features = [
                _osm_feature(way)
                for way in osm.ways(payload)
                if (way.get("tags") or {}).get("name")
            ]
            path.write_text(json.dumps({"type": "FeatureCollection", "features": features}))
            record.add_file(path, root=directory)
            print(f"    trails-national/{unit}-osm: {len(features)} named ways", flush=True)
    record.write(directory)


def _osm_feature(way: dict[str, Any]) -> dict[str, Any]:
    """An OSM way as the NPS layer would carry it, so the catalogue reads both alike."""
    tags = way.get("tags") or {}
    uses = ["Hike"]
    if tags.get("horse") in ("yes", "designated", "permissive"):
        uses.append("Horse")
    if tags.get("bicycle") in ("yes", "designated", "permissive"):
        uses.append("Bicycle")
    return {
        "type": "Feature",
        "properties": {
            "TRLNAME": tags["name"],
            "TRLUSE": ", ".join(uses),
            "SOURCE": "osm",
            "OSM_ID": way.get("id"),
        },
        "geometry": {
            "type": "LineString",
            "coordinates": [[node["lon"], node["lat"]] for node in way.get("geometry") or []],
        },
    }


# MARK: - Elevation


def sample_elevations(raw_trails: Path, unit_outlines: dict[str, list[outline.Polygon]]) -> Path:
    """Sample 3DEP at every station of every catalogue trail, caching what comes back.

    The cache sits beside the trails in the raw store, keyed by station position, so a
    rebuild — or a second run after an interruption — only asks for what it lacks.
    """
    directory = raw_trails.parent / "trail-elevation"
    directory.mkdir(parents=True, exist_ok=True)
    record = FetchRecord(source=ELEVATION_TERMS, fetched_at=rawstore.utc_now())
    for _, row in reference_content.national_park_rows():
        code = row["npsParkCode"].upper()
        cache_path = directory / f"{code}.json"
        cache: dict[str, float | None] = (
            json.loads(cache_path.read_text()) if cache_path.exists() else {}
        )
        wanted: list[tuple[float, float]] = []
        for chain in _park_chains(raw_trails, row, unit_outlines):
            for station in measure.resample(chain, STATION_INTERVAL_M):
                key = _key(station.longitude, station.latitude)
                if key not in cache:
                    cache[key] = None
                    wanted.append((station.longitude, station.latitude))
        if not wanted:
            continue
        print(f"    trail-elevation/{code}: sampling {len(wanted)} stations", flush=True)
        batches = [
            wanted[start : start + SAMPLES_PER_REQUEST]
            for start in range(0, len(wanted), SAMPLES_PER_REQUEST)
        ]
        with ThreadPoolExecutor(max_workers=SAMPLE_WORKERS) as pool:
            for result in pool.map(_sample_batch, batches):
                cache.update(result)
        cache_path.write_text(json.dumps(cache, separators=(",", ":")))
        record.add_file(cache_path, root=directory)
    record.write(directory)
    return directory


def _sample_batch(points: list[tuple[float, float]]) -> dict[str, float | None]:
    geometry = json.dumps({
        "points": [[round(lon, 6), round(lat, 6)] for lon, lat in points],
        "spatialReference": {"wkid": 4326},
    })
    form = {
        "geometry": geometry,
        "geometryType": "esriGeometryMultipoint",
        "returnFirstValueOnly": "true",
        "interpolation": "RSP_BilinearInterpolation",
        "f": "json",
    }
    result: dict[str, float | None] = {_key(lon, lat): None for lon, lat in points}
    for attempt in range(4):
        try:
            with httpx.Client(timeout=180, headers={"User-Agent": http.USER_AGENT}) as client:
                response = client.post(ELEVATION_SAMPLES, data=form)
            payload = response.json()
            if "samples" not in payload:
                raise http.FetchError(str(payload.get("error")))
            for sample in payload["samples"]:
                index = sample.get("locationId")
                value = _number(sample.get("value"))
                if index is None or not 0 <= index < len(points):
                    continue
                lon, lat = points[index]
                # 3DEP's no-data value is a large negative number, not an absence.
                result[_key(lon, lat)] = value if value is not None and value > -1000 else None
            return result
        except (httpx.HTTPError, ValueError, http.FetchError):
            if attempt == 3:
                print(f"    trail-elevation: a batch of {len(points)} failed, left unmeasured")
                return result
            import time

            time.sleep(4 * (attempt + 1))
    return result


def _key(longitude: float, latitude: float) -> str:
    return f"{longitude:.5f},{latitude:.5f}"


def _number(value: Any) -> float | None:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return number if math.isfinite(number) else None


# MARK: - Build


def build(
    raw_trails: Path,
    unit_outlines: dict[str, list[outline.Polygon]],
    pois: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    """Every catalogue trail, as the app's ``Trail`` decodes it."""
    elevation_dir = raw_trails.parent / "trail-elevation"
    sights_by_place: dict[str, list[dict[str, Any]]] = {}
    for poi in pois:
        if poi["kind"] in ("sight", "viewpoint"):
            sights_by_place.setdefault(poi["placeID"], []).append(poi)

    catalogue: list[dict[str, Any]] = []
    for _, row in reference_content.national_park_rows():
        code = row["npsParkCode"].upper()
        cache_path = elevation_dir / f"{code}.json"
        cache = json.loads(cache_path.read_text()) if cache_path.exists() else {}

        def sampler(longitude: float, latitude: float, cache: dict = cache) -> float | None:
            return cache.get(_key(longitude, latitude))

        segments = _park_segments(raw_trails, row, unit_outlines)
        seen: set[str] = set()
        for name, group in sorted(trails.group_by_name(segments).items()):
            if name.startswith("Unnamed trail"):
                continue
            trail = _trail(row, name, group, sampler, sights_by_place.get(row["id"], []))
            if trail is None or trail["id"] in seen:
                continue
            seen.add(trail["id"])
            catalogue.append(trail)
    measured = sum(1 for trail in catalogue if "gainMetres" in trail)
    kilometres = sum(trail["lengthMetres"] for trail in catalogue) / 1000
    print(
        f"    trails: {len(catalogue)} in {len({t['placeID'] for t in catalogue})} parks, "
        f"{kilometres:,.0f} km, {measured} with elevation"
    )
    return catalogue


def _trail(
    row: dict[str, Any],
    name: str,
    group: list[dict[str, Any]],
    sampler: measure.ElevationSampler,
    sights: list[dict[str, Any]],
) -> dict[str, Any] | None:
    chains = trails.chain(group)
    measurements = [
        measure.measure(
            chain,
            sampler,
            interval_m=STATION_INTERVAL_M,
            smoothing_window_m=SMOOTHING_WINDOW_M,
            profile_points=PROFILE_POINTS,
        )
        for chain in chains
    ]
    length = sum(item.length_m for item in measurements)
    if length < MIN_LENGTH_M:
        return None
    properties = group[0]["properties"]
    use = (properties.get("TRLUSE") or "").strip()
    if _is_water_route(use):
        return None
    paths = [
        simplified
        for chain in chains
        if len(simplified := outline.simplify(list(chain), LINE_TOLERANCE_DEGREES)) >= 2
    ]
    trail: dict[str, Any] = {
        "id": ids.trail_id(row["slug"], name),
        "placeID": row["id"],
        "name": _clean_name(name),
        "lengthMetres": round(length, 1),
        "paths": [outline.encode(path) for path in paths],
    }
    if len(chains) == 1 and distance_m(chains[0][0], chains[0][-1]) <= 60 and length > 500:
        trail["routeType"] = "loop"
    if all(item.has_elevation for item in measurements):
        longest = max(range(len(measurements)), key=lambda index: measurements[index].length_m)
        trail |= {
            "gainMetres": round(sum(item.elevation_gain_m or 0 for item in measurements), 1),
            "lossMetres": round(sum(item.elevation_loss_m or 0 for item in measurements), 1),
            "highPointMetres": round(max(item.high_point_m or 0 for item in measurements), 1),
            "lowPointMetres": round(min(item.low_point_m or 0 for item in measurements), 1),
            "profile": [
                [round(point.distance_m), round(point.elevation_m, 1)]
                for point in measurements[longest].profile
            ],
        }
    if properties.get("SOURCE") == "osm":
        trail["source"] = "osm"
    notes = (properties.get("SEASDESC") or "").strip()
    if notes and notes.lower() not in ("unknown", "n/a", "none"):
        trail["seasonalNotes"] = notes
    if "bicycle" in use.lower() or "bike" in use.lower():
        trail["bikesAllowed"] = True
    # Some parks record a maintenance level in the use field; that is not who may use it.
    if use and use.lower() != "unknown" and "maintenance" not in use.lower():
        parts = (part.strip() for part in use.replace("|", ",").split(","))
        trail["uses"] = ", ".join(part for part in parts if part)
    on_route = _sights_along(chains, sights)
    if on_route:
        trail["sightIDs"] = on_route
    if features := _features(name):
        trail["features"] = features
    return trail


def _name_from_label(properties: dict[str, Any]) -> None:
    """Give a segment its trail's name where the park left ``TRLNAME`` empty.

    Acadia, among others, names its trails only in the map label, or in the OpenStreetMap
    tags its GIS staff copied into ``NOTES``. Either is the park's own name for the trail.
    """
    if (properties.get("TRLNAME") or "").strip():
        return
    label = (properties.get("MAPLABEL") or "").strip()
    if not label:
        try:
            notes = json.loads(properties.get("NOTES") or "{}")
        except (TypeError, ValueError):
            notes = {}
        label = (notes.get("name") or "").strip() if isinstance(notes, dict) else ""
    if label:
        properties["TRLNAME"] = label


def _is_water_route(use: str) -> bool:
    """A paddling or boat route the trails layer carries alongside the footpaths."""
    lowered = use.lower()
    on_foot = any(word in lowered for word in ("hik", "pedestrian", "foot", "walk"))
    return "watercraft" in lowered and not on_foot


def _sights_along(chains: list[list[Coordinate]], sights: list[dict[str, Any]]) -> list[str]:
    """The guide's sights a trail passes, in walking order along its longest part."""
    if not sights or not chains:
        return []
    stations = [
        (station.distance_m, (station.longitude, station.latitude))
        for station in measure.resample(chains[0], 60.0)
    ]
    passed: list[tuple[float, str]] = []
    for sight in sights:
        location = sight["location"]
        point = (location["longitude"], location["latitude"])
        nearest = min(stations, key=lambda s: distance_m(s[1], point), default=None)
        if nearest and distance_m(nearest[1], point) <= SIGHT_REACH_M:
            passed.append((nearest[0], sight["id"]))
    return [sight_id for _, sight_id in sorted(passed)]


# Words in a trail's own name that say what it leads to. Only the name is read: a trail
# called "Lake Trail" is tagged lake, and one that passes a lake unnamed is not.
_FEATURE_WORDS = {
    "waterfall": ("falls", "waterfall", "cascade"),
    "summit": ("peak", "summit", "mountain", "mount ", "dome", "butte"),
    "lake": ("lake", "pond", "lakes"),
    "arch": ("arch", "arches", "bridge"),
    "beach": ("beach",),
    "canyon": ("canyon", "gorge", "narrows"),
    "glacier": ("glacier",),
    "cave": ("cave", "cavern"),
    "meadow": ("meadow", "meadows"),
}


def _features(name: str) -> list[str]:
    text = f" {name.lower()} "
    return [
        feature
        for feature, words in _FEATURE_WORDS.items()
        if any(f" {word.strip()} " in text or f" {word.strip()}s " in text for word in words)
    ]


def _clean_name(name: str) -> str:
    return " ".join(name.split())


def _park_segments(
    raw_trails: Path, row: dict[str, Any], unit_outlines: dict[str, list[outline.Polygon]]
) -> list[dict[str, Any]]:
    """A park's trail segments: its own unit's, kept where they lie in its outline."""
    features: list[dict[str, Any]] = []
    for code in {row["npsParkCode"].upper(), reference_content.api_code(row).upper()}:
        for name in (f"{code}.geojson", f"{code}-osm.geojson"):
            path = raw_trails / name
            if path.exists():
                features.extend(json.loads(path.read_text()).get("features") or [])
    for feature in features:
        _name_from_label(feature.get("properties") or {})
    segments = trails.segments_of(features)
    polygons = unit_outlines.get(row["npsParkCode"].upper())
    if not polygons:
        return segments
    box = outline.bbox(polygons)
    if box is None:
        return segments
    south, west, north, east = box
    pad = BOUNDARY_BUFFER_DEGREES

    def inside(segment: dict[str, Any]) -> bool:
        line = segment["coordinates"]
        lon, lat = line[len(line) // 2]
        if not (south - pad <= lat <= north + pad and west - pad <= lon <= east + pad):
            return False
        return outline.contains(polygons, lon, lat) or any(
            outline.contains(polygons, lon + dx, lat + dy)
            for dx in (-pad, pad)
            for dy in (-pad, pad)
        )

    return [segment for segment in segments if inside(segment)]


def _park_chains(
    raw_trails: Path, row: dict[str, Any], unit_outlines: dict[str, list[outline.Polygon]]
) -> list[list[Coordinate]]:
    chains: list[list[Coordinate]] = []
    for name, group in trails.group_by_name(_park_segments(raw_trails, row, unit_outlines)).items():
        if name.startswith("Unnamed trail"):
            continue
        for chain in trails.chain(group):
            chains.append(chain)
    return chains
