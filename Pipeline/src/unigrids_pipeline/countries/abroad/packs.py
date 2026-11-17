"""Offline packs for parks abroad: ``fetch``/``derive``/``build --park jp-np-chubusangaku``.

A pack abroad is the same four files as at home (ADR 0006, 0010), drawn by the same
renderer. What changes is where each layer comes from:

| Layer | At home | Abroad |
|---|---|---|
| Outline | NPS boundaries | MOE's ``nps.zip`` (Japan), Naturvernområder (Norway) |
| Relief and trail profiles | 3DEP at 10 m | Copernicus GLO-30 at 30 m |
| Roads and water | OpenStreetMap | OpenStreetMap |
| Trails drawn | NPS Public Trails | Turrutebasen's segments (Norway), OSM footpaths otherwise |
| ``trails.json`` | measured NPS trails | the park's share of the catalogue abroad |

The deepest zoom is capped at 15: a 30 m model has nothing to show at zoom 16's two
metres a pixel, and the renderer would only enlarge it. The manifest carries the credit
line the app draws on the map (``"attribution"``), since a pack abroad owes different
sources than the four US packs.
"""

from __future__ import annotations

import dataclasses
import json
from pathlib import Path
from typing import Any

from ... import config, coverage, dem, ids, outline, packs, rawstore, render
from ...geo import BoundingBox
from ...rawstore import FetchRecord, SourceTerms
from ...sources import http, osm
from . import elevation, outlines, trails

COUNTRIES = outlines.COUNTRIES
MAX_ZOOM = 15
"""The deepest zoom a pack abroad renders: GLO-30's 30 m does not support 16."""
GROUND_RESOLUTION_M = 30.0
ELEVATION_SOURCE = "elevation-copernicus"
OSM_SOURCE = "osm"

# OSM ways drawn as trails where OpenStreetMap is the trail source: footpaths, not the
# sidewalks and crossings a town's footways are.
DRAWN_PATHS = frozenset({"path", "footway", "bridleway", "steps"})

COUNTRY_NAMES = {
    "jp": "Japan", "no": "Norway", "nz": "New Zealand", "ca": "Canada", "au": "Australia",
}
NOT_AFFILIATED = {
    "jp": (
        "It is **not** a product of Japan's Ministry of the Environment and implies no "
        "affiliation with it or endorsement by it. It carries no national park mark."
    ),
    "no": (
        "It is **not** a product of Miljødirektoratet or Norway's national park boards and "
        "implies no affiliation or endorsement. It carries no Norges nasjonalparker symbol."
    ),
    "nz": (
        "It is **not** a product of the Department of Conservation Te Papa Atawhai and "
        "implies no affiliation with it or endorsement by it. It carries no DOC logo."
    ),
    "ca": (
        "It is **not** a product of Parks Canada and implies no affiliation with it or "
        "endorsement by it. It carries neither Parks Canada's beaver symbol nor its wordmark."
    ),
    "au": (
        "It is **not** a product of Parks Australia or of any Australian state or territory "
        "park agency, and implies no affiliation with any of them or endorsement by them. It "
        "carries none of their logos."
    ),
}


def is_abroad(code: str) -> bool:
    """Whether ``--park`` names a park abroad (``jp-np-…``, ``no-np-…``) rather than an
    NPS code."""
    parts = code.lower().split("-")
    return len(parts) >= 3 and parts[0] in COUNTRIES


def park(place_id: str) -> config.Park:
    """A park abroad as the pack steps carry one: its place ID stands in for a unit code."""
    entry = outlines.park(place_id.lower())
    return config.Park(
        unit_code=entry["id"],
        place_id=entry["id"],
        slug=trails.park_slug(entry["id"]),
        name=f"{entry['name']} National Park",
    )


# MARK: - fetch


def fetch(place_id: str, source: str | None = None, *, refresh: bool = False) -> None:
    """The keyless sources a pack abroad needs, into ``raw/<today>/``."""
    target = park(place_id)
    country = outlines.country_of(target.place_id)
    wanted = (source,) if source else ("boundaries", "trails", "elevation", "osm")
    version = rawstore.today()
    polygons = outlines.outline_of(target.place_id)

    if "boundaries" in wanted:
        path = outlines.write_feature(target.place_id, polygons)
        print(f"    outline of {target.name}: {sum(len(p) for p in polygons)} rings, {path}")

    if "trails" in wanted:
        trails.fetch(country, [outlines.park(target.place_id)], {target.place_id: polygons},
                     refresh=refresh)

    box = render_box(polygons)
    if "elevation" in wanted:
        directory = config.RAW_DIR / version / ELEVATION_SOURCE / target.place_id
        if (directory / "index.json").exists() and not refresh:
            print(f"    {ELEVATION_SOURCE}: already built today (--refresh to redo)")
        else:
            model = elevation.CopernicusDEM(online=True)
            missing = model.fetch_box(box.south, box.west, box.north, box.east)
            print(f"    Copernicus GLO-30 tiles: {missing} downloaded for the render box")
            index = elevation.write_grid(
                directory, box, ground_resolution_m=GROUND_RESOLUTION_M, dem=model
            )
            model.close()
            record = FetchRecord(source=elevation.TERMS, fetched_at=rawstore.utc_now())
            record.add_request(
                elevation.BUCKET,
                {"tiles": [elevation.tile_name(*tile) for tile in elevation.tiles_for_box(
                    box.south, box.west, box.north, box.east
                )]},
            )
            record.write(directory.parent)
            print(f"    {index['columns']}×{index['rows']} px elevation grid at "
                  f"{GROUND_RESOLUTION_M:.0f} m")

    if "osm" in wanted:
        directory = rawstore.version_directory(OSM_SOURCE, version)
        path = directory / f"{target.place_id}.json"
        if path.exists() and not refresh:
            print(f"    {OSM_SOURCE}: already fetched today (--refresh to redo)")
        else:
            print("    OpenStreetMap roads and water, via Overpass")
            record = _carried_record(directory, SourceTerms(**osm.TERMS), path.name)
            try:
                with trails.client() as session:
                    elements, asked = trails.overpass_box(session, box, osm.build_query)
            except http.FetchError as error:
                print(f"    {OSM_SOURCE}: not fetched ({error}); run again later")
                return
            for endpoint, query in asked:
                record.add_request(endpoint, {"data": query})
            payload = {"elements": elements}
            path.write_text(json.dumps(payload))
            record.add_file(path, root=directory)
            record.write(directory)
            print(f"    {len(payload.get('elements', []))} OSM elements")


def render_box(polygons: list[outline.Polygon]) -> BoundingBox:
    """The extent relief and roads are fetched for: the park, buffered, as at home."""
    south, west, north, east = outline.bbox(polygons) or (0.0, 0.0, 0.0, 0.0)
    box = BoundingBox(west=west, south=south, east=east, north=north)
    return box.buffered(config.DEFAULT_PACK_SETTINGS.boundary_buffer_m * 1.5)


# MARK: - derive


def derive(place_id: str) -> list[dict[str, Any]]:
    """The park's trails, measured as the catalogue abroad measures them, written to
    ``work/<place-id>/trails.json``."""
    target = park(place_id)
    records = _catalogue(target)
    directory = config.WORK_DIR / target.place_id
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "trails.json").write_text(json.dumps(_trails_file(target, records), indent=1,
                                                      ensure_ascii=False) + "\n")
    measured = sum(1 for record in records if "gainMetres" in record)
    total_km = sum(record["lengthMetres"] for record in records) / 1000
    print(f"    {len(records)} trails, {measured} with elevation, {total_km:.1f} km of trail")
    for record in sorted(records, key=lambda item: -item["lengthMetres"])[:8]:
        gain = (
            f"{record['gainMetres']:,.0f} m up" if "gainMetres" in record else "no elevation"
        )
        print(f"      {record['name'][:36]:<36} {record['lengthMetres'] / 1000:>6.2f} km  {gain}")
    return records


def _catalogue(target: config.Park) -> list[dict[str, Any]]:
    country = outlines.country_of(target.place_id)
    polygons = outlines.outline_of(target.place_id, online=False)
    # Identifiers resolve against the committed registry without saving it: the reference
    # build pins them when it ships the catalogue.
    return trails.build(
        country,
        [outlines.park(target.place_id)],
        {target.place_id: polygons},
        {},
        online=False,
        registry=ids.country_registry(country, "trails"),
    )


def _trails_file(target: config.Park, records: list[dict[str, Any]]) -> dict[str, Any]:
    return {
        "placeID": target.place_id,
        "measurement": trails.measurement_method(),
        "trails": records,
    }


# MARK: - build


def build(
    place_id: str,
    *,
    settings: config.PackSettings | None = None,
    zoom_by_area: bool = False,
) -> packs.PackResult:
    """Render one park's pack abroad into ``out/packs/<place-id>/``."""
    target = park(place_id)
    country = outlines.country_of(target.place_id)
    settings = settings or config.DEFAULT_PACK_SETTINGS

    boundary_directory = rawstore.require(outlines.SOURCES[country], f"{target.place_id}.geojson")
    elevation_directory = rawstore.require(ELEVATION_SOURCE, f"{target.place_id}/index.json")
    osm_directory = rawstore.require(OSM_SOURCE, f"{target.place_id}.json")
    boundary_features = _read_features(boundary_directory / f"{target.place_id}.geojson")
    rings = [ring for ring in coverage.rings(boundary_features) if not ring.is_hole]
    area = coverage.area_km2(rings)
    settings = dataclasses.replace(
        settings, max_zoom=deepest_zoom(area, settings.max_zoom, by_area=zoom_by_area)
    )
    print(f"    {area:,.0f} km², so tiles to zoom {settings.max_zoom}")

    osm_ways = osm.ways(
        water_as_rings(json.loads((osm_directory / f"{target.place_id}.json").read_text()))
    )
    grid = dem.ElevationGrid.load(elevation_directory / target.place_id)
    records = _catalogue(target)
    drawn, trail_sources = trail_features(country, target.place_id, osm_ways)
    print(
        f"    {len(drawn)} trail lines drawn, {len(records)} catalogue trails, "
        f"{len(osm_ways)} OSM ways, {grid.columns}×{grid.rows} elevation grid "
        f"({grid.coverage:.1%} covered)"
    )

    sources = [
        entry
        for directory in (
            boundary_directory,
            *trail_sources,
            elevation_directory,
            osm_directory,
        )
        if (entry := _source_entry(directory))
    ]

    directory = config.OUT_DIR / "packs" / target.place_id
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "trails.json").write_text(
        json.dumps(_trails_file(target, records), indent=1, ensure_ascii=False) + "\n"
    )

    park_coverage = coverage.ParkCoverage(
        coverage.rings(boundary_features),
        buffer_m=settings.boundary_buffer_m,
        max_zoom=settings.max_zoom,
        extra=packs._box_of_trails(drawn),
    )
    layers = render.layers_from_sources(osm_ways, drawn, boundary_features)
    credit = attribution_line(country, records, drawn_from=trail_sources)
    measurements, tile_bytes = packs.render_tiles(
        directory / "tiles.mbtiles",
        park_coverage,
        layers,
        grid,
        settings,
        name=f"{target.name} offline pack",
        description=(
            "Topo-style tiles rendered from Copernicus GLO-30 elevation and OpenStreetMap "
            f"roads and water, with {_trail_words(trail_sources)}. Not an official product."
        ),
        attribution=credit,
    )

    _write_attribution(directory, target, country, sources, settings, credit)
    length_km = sum(record["lengthMetres"] for record in records) / 1000
    measured = sum(1 for record in records if "gainMetres" in record)
    measured_km = sum(r["lengthMetres"] for r in records if "gainMetres" in r) / 1000
    _write_manifest(
        directory, target, country, settings, park_coverage, measurements, sources, credit,
        trail_count=len(records), measured_trail_count=measured, trail_length_km=length_km,
    )
    files = {
        path.name: path.stat().st_size for path in sorted(directory.iterdir()) if path.is_file()
    }
    result = packs.PackResult(
        park=target,
        directory=directory,
        settings=settings,
        bounds=park_coverage.bounds,
        render_bounds=park_coverage.render_bounds,
        area_km2=park_coverage.area_km2,
        zooms=measurements,
        files=files,
        trail_count=len(records),
        measured_trail_count=measured,
        trail_length_km=length_km,
        elevation_coverage=measured_km / length_km if length_km else 0.0,
        vector_counts=layers.counts(),
        sources=sources,
        tile_bytes=tile_bytes,
        mbtiles_bytes=(directory / "tiles.mbtiles").stat().st_size,
    )
    print(
        f"    pack: {result.total_bytes / 1e6:.2f} MB for {result.area_km2:,.0f} km² "
        f"({result.bytes_per_km2() / 1e3:.1f} KB/km²), zoom {settings.min_zoom}–"
        f"{settings.max_zoom}"
    )
    return result


def deepest_zoom(area_km2: float, requested: int, *, by_area: bool) -> int:
    """The pack's deepest zoom: by area as at home (ADR 0006), or as asked, and never past
    :data:`MAX_ZOOM`, since a 30 m model has nothing to draw at zoom 16."""
    zoom = config.max_zoom_for_area(area_km2) if by_area else requested
    if zoom > MAX_ZOOM:
        print(f"    zoom {zoom} capped at {MAX_ZOOM}: GLO-30's 30 m has nothing to add")
    return min(zoom, MAX_ZOOM)


def water_as_rings(payload: dict[str, Any]) -> dict[str, Any]:
    """The payload with each water multipolygon's member ways joined into closed rings.

    The renderer fills every way of a water relation as a polygon of its own, which is
    right for a pond drawn as one closed way and wrong for Gjende, mapped as a dozen
    shoreline ways: each comes out as a sliver closed by a straight chord. Joined first,
    the lake fills as one shape. Islands (inner rings) are not cut out, since the renderer
    draws no holes. The US packs' build applies it too (``steps.build``).
    """
    from ..jp import geometry

    elements: list[dict[str, Any]] = []
    for element in payload.get("elements") or []:
        if element.get("type") != "relation":
            elements.append(element)
            continue
        for index, polygon in enumerate(geometry.osm_polygons(element)):
            ring = polygon[0]
            elements.append({
                "type": "way",
                "id": element.get("id"),
                "ring": index,
                "tags": element.get("tags") or {},
                "geometry": [{"lon": lon, "lat": lat} for lon, lat in [*ring, ring[0]]],
            })
    return {**payload, "elements": elements}


def trail_features(
    country: str, place_id: str, osm_ways: list[dict[str, Any]]
) -> tuple[list[dict[str, Any]], list[Path]]:
    """The lines a pack draws as trails, and the raw directories they came from.

    Norway draws every Turrutebasen segment in the park's box, the routes the catalogue
    names and the ones the database leaves unnamed alike: both are marked on the ground.
    Where Turrutebasen has nothing, and in Japan, the footpaths in the pack's own
    OpenStreetMap extract are drawn — named or not, since most mountain paths in OSM carry
    no name. Never both, or a path would be printed twice, half a pixel apart.
    """
    if country == "no":
        directory = rawstore.latest(trails.TURRUTEBASEN, f"{place_id}.geojson")
        if directory is not None:
            features = _read_features(directory / f"{place_id}.geojson")
            if features:
                return features, [directory]
    drawn = [
        {
            "type": "Feature",
            "properties": {"highway": (way.get("tags") or {}).get("highway")},
            "geometry": {
                "type": "LineString",
                "coordinates": [[node["lon"], node["lat"]] for node in way["geometry"]],
            },
        }
        for way in osm_ways
        if (way.get("tags") or {}).get("highway") in DRAWN_PATHS
        and (way.get("tags") or {}).get("footway") not in ("sidewalk", "crossing")
        and len(way.get("geometry") or []) >= 2
    ]
    return drawn, []


def attribution_line(
    country: str, records: list[dict[str, Any]], *, drawn_from: list[Path]
) -> str:
    """The credit the map carries: "Elevation Copernicus GLO-30 · Roads and water ©
    OpenStreetMap contributors (ODbL) · Trails …", naming the trail sources this pack
    actually uses."""
    sources = {record.get("source") for record in records}
    if drawn_from:
        sources.add("kartverket")
    else:
        sources.add("osm")
    names = [name for key, name in (("kartverket", "Kartverket"), ("parksCanada", "Parks Canada"),
                                    ("qpws", "Queensland Parks and Wildlife Service"),
                                    ("osm", "OpenStreetMap"))
             if key in sources]
    return (
        "Elevation Copernicus GLO-30 · Roads and water © OpenStreetMap contributors (ODbL) · "
        f"Trails {'/'.join(names)}"
    )


def _trail_words(trail_sources: list[Path]) -> str:
    return "Kartverket's marked routes" if trail_sources else "OpenStreetMap footpaths"


def _read_features(path: Path) -> list[dict[str, Any]]:
    return json.loads(path.read_text()).get("features") or []


def _source_entry(directory: Path) -> dict[str, str] | None:
    terms = rawstore.read_terms(directory)
    if terms is None:
        return None
    return {
        "identifier": terms.identifier,
        "title": terms.title,
        "url": terms.url,
        "licence": terms.licence,
        "attribution": terms.attribution,
        "notes": terms.notes,
        "version": rawstore.version_of(directory),
    }


def _carried_record(directory: Path, terms: SourceTerms, replacing: str) -> FetchRecord:
    """A ``source.json`` that keeps what other parks fetched into the same folder today."""
    record = FetchRecord(source=terms, fetched_at=rawstore.utc_now())
    existing = directory / "source.json"
    if existing.exists():
        payload = json.loads(existing.read_text())
        record.requests = list(payload.get("requests") or [])
        record.files = [
            entry for entry in payload.get("files") or [] if entry["path"] != replacing
        ]
    return record


def _write_attribution(
    directory: Path,
    target: config.Park,
    country: str,
    sources: list[dict[str, str]],
    settings: config.PackSettings,
    credit: str,
) -> None:
    lines = [
        f"# Attribution — {target.name} offline pack",
        "",
        f"This pack ships inside the Unigrids app. {NOT_AFFILIATED[country]}",
        "",
        f"The map carries this credit: {credit}",
        "",
        "## Sources",
        "",
    ]
    for source in sources:
        lines += [
            f"### {source.get('title') or source['identifier']}",
            "",
            f"- Licence: {source.get('licence', 'unknown')}",
            f"- Attribution: {source.get('attribution', '—')}",
            f"- Fetched: {source.get('version', 'unknown')} from {source.get('url', '—')}",
        ]
        if source.get("notes"):
            lines.append(f"- Notes: {source['notes']}")
        lines.append("")
    lines += [
        "## What this pack owes",
        "",
        "**Copernicus.** The relief and every elevation figure are "
        f"{elevation.TERMS.attribution}. {elevation.LIABILITY} GLO-30 is a surface model:",
        "forest canopy and buildings are in its heights.",
        "",
        "**OpenStreetMap.** The tiles are a Produced Work under the ODbL and owe attribution.",
        "Where `trails.json` carries lines taken from OpenStreetMap (`\"source\": \"osm\"`), it",
        "is a Derivative Database: attributed, and available under the ODbL like the",
        "catalogue it is part of.",
        "",
    ]
    if country == "no":
        lines += [
            "**Kartverket.** Turrutebasen's routes and grades are CC BY 4.0, «©Kartverket».",
            "Grades are quoted as Kartverket's codes, never its criteria text.",
            "",
        ]
    if country == "nz":
        lines += [
            "**Department of Conservation.** Park outlines from Public Conservation Land and",
            "trail lines and categories from DOC Tracks are CC BY 4.0, Crown Copyright:",
            "Department of Conservation Te Papa Atawhai.",
            "",
        ]
    if country == "ca":
        lines += [
            "**Parks Canada and Environment and Climate Change Canada.** Park outlines from the",
            "Canadian Protected and Conserved Areas Database (CPCAD) and trail lines and",
            "difficulty ratings from Parks Canada's trails data are used under the Open",
            "Government Licence – Canada.",
            "",
        ]
    if country == "au":
        lines += [
            "**Australian Government and the State of Queensland.** Park outlines from the",
            "Collaborative Australian Protected Areas Database (CAPAD 2024, © Commonwealth of",
            "Australia, DCCEEW) and, in Queensland, trail lines and track classes from the",
            "Queensland Parks and Wildlife Service's access data (© State of Queensland) are",
            "used under CC BY 4.0.",
            "",
        ]
    lines += [
        f"Rendered at zoom {settings.min_zoom}–{settings.max_zoom}, "
        f"{settings.tile_size} px tiles, {settings.tile_format}.",
        "",
    ]
    (directory / "ATTRIBUTION.md").write_text("\n".join(lines))


def _write_manifest(
    directory: Path,
    target: config.Park,
    country: str,
    settings: config.PackSettings,
    park_coverage: coverage.ParkCoverage,
    measurements: list[packs.ZoomMeasurement],
    sources: list[dict[str, str]],
    credit: str,
    *,
    trail_count: int,
    measured_trail_count: int,
    trail_length_km: float,
) -> None:
    manifest = {
        "packVersion": 1,
        "placeID": target.place_id,
        "country": country,
        "name": target.name,
        "generatedAt": rawstore.utc_now(),
        "bounds": {
            "park": park_coverage.bounds.as_list(),
            "rendered": park_coverage.render_bounds.as_list(),
            "bufferMetres": settings.boundary_buffer_m,
            "areaSquareKilometres": round(park_coverage.area_km2, 1),
        },
        "tiles": {
            "file": "tiles.mbtiles",
            "scheme": "tms",
            "rowOrder": "MBTiles stores TMS rows, south first; flip y for MKTileOverlay's XYZ",
            "size": settings.tile_size,
            "format": settings.tile_format,
            "minZoom": settings.min_zoom,
            "maxZoom": settings.max_zoom,
            "byZoom": [measurement.as_json() for measurement in measurements],
        },
        "elevation": {
            "model": "Copernicus GLO-30 (surface model)",
            "groundResolutionMetres": GROUND_RESOLUTION_M,
            "credit": elevation.CREDIT,
        },
        "trails": {
            "file": "trails.json",
            "count": trail_count,
            "measuredCount": measured_trail_count,
            "totalLengthKilometres": round(trail_length_km, 2),
        },
        "sources": sources,
        "notIncludedYet": [
            "sights, huts and visitor centres (they are in the bundled reference data)",
            "guide content",
        ],
        "attribution": credit,
        "attributionFile": "ATTRIBUTION.md",
    }
    (directory / "manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n"
    )

