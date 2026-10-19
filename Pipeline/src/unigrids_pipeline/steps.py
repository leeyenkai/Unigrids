"""The six pipeline steps (SPECIFICATION.md §12).

Three of them are built, for one park. ``fetch``, ``derive`` and ``build`` do what an
offline pack needs for Zion: the keyless sources, the trail measurements, and the rendered
pack with its size measured — which is ``docs/mvp-scope.md``'s last open exit criterion
and §16's "riskiest step".

The other three still raise ``StepNotBuiltError`` with their contracts, and so do the
parts of ``fetch`` that need a key nobody has supplied. A labelled stub is honest; a step
that silently wrote nothing would be worse (``AGENTS.md`` §10).
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from . import config, coverage, dem, packs, rawstore, sizereport, trails
from .geo import BoundingBox
from .rawstore import FetchRecord, SourceTerms
from .sources import arcgis, http, osm, threedep


class StepNotBuiltError(NotImplementedError):
    """Raised by a step that is specified but not implemented yet."""


# Sources `fetch` can reach without a key. The NPS API and RIDB both need one, and the
# pipeline says so rather than failing somewhere deeper.
KEYLESS_SOURCES = ("boundaries", "trails", "elevation", "osm")
KEYED_SOURCES = {
    "nps": (
        "the NPS API needs a free key. Copy Pipeline/.env.example to Pipeline/.env and "
        "set NPS_API_KEY, then this source can be built."
    ),
    "ridb": "RIDB needs a free key; set RIDB_API_KEY in Pipeline/.env.",
    "padus": (
        "PAD-US 4.1 is a multi-gigabyte download and is only needed for state parks and "
        "other agencies' land (tier 2–4, 0.2.0+). National park boundaries come from the "
        "NPS boundary service instead."
    ),
}

NPS_TRAILS_TERMS = SourceTerms(
    identifier="nps-public-trails",
    title="NPS Public Trails (national dataset, ArcGIS MapServer)",
    url=arcgis.TRAILS_LAYER,
    licence="Public NPS dataset, public release subset",
    attribution="Trail data: National Park Service Public Trails dataset",
    notes=(
        "Official visitor-use trails maintained by park GIS staff. Completeness varies by "
        "park: a route that is not a maintained trail (Zion's Narrows, for instance) is "
        "correctly absent, and so are some connectors."
    ),
)

NPS_BOUNDARY_TERMS = SourceTerms(
    identifier="nps-boundaries",
    title="NPS Land Resources Division boundaries",
    url=arcgis.BOUNDARY_LAYER,
    licence="Public NPS dataset",
    attribution="Boundaries: National Park Service, Land Resources Division",
    notes="Used for the pack extent and for the all-parks tile-count extrapolation.",
)


def fetch(
    source: str | None = None,
    *,
    park_code: str = config.DEFAULT_PARK,
    refresh: bool = False,
) -> None:
    """Pull each source into ``raw/``, versioned by date.

    Sources and their terms are in ``SPECIFICATION.md`` §12. Two things matter in the
    implementation:

    * **Version every download by date** so a dataset can be rebuilt exactly, and so a
      change in a source can be told apart from a change in the pipeline.
    * **Respect the rate limits.** The NPS key is per-key rate-limited and the same key
      ships inside the app, so the pipeline must not be the thing that exhausts it. In the
      same spirit, a source already fetched today is left alone unless ``refresh`` says
      otherwise: re-running the step should not pull sixty megabytes off a government
      service again to get the same bytes.
    """
    if source in KEYED_SOURCES:
        raise StepNotBuiltError(f"fetch({source}) is not built: {KEYED_SOURCES[source]}")
    if source is not None and source not in KEYLESS_SOURCES:
        known = ", ".join((*KEYLESS_SOURCES, *KEYED_SOURCES))
        raise SystemExit(f"unknown source {source!r}. Known sources: {known}")

    park = config.park(park_code)
    wanted = (source,) if source else KEYLESS_SOURCES
    version = rawstore.today()

    def needed(name: str, *files: str) -> bool:
        if name not in wanted:
            return False
        directory = config.RAW_DIR / version / name
        if not refresh and all((directory / file).exists() for file in files):
            print(f"    {name}: already fetched today, leaving it alone (--refresh to redo)")
            return False
        return True

    fetch_boundaries = needed("boundaries", f"{park.place_id}.geojson", "national-parks.geojson")
    fetch_trails = needed("trails", f"{park.place_id}.geojson")
    fetch_elevation = needed("elevation", f"{park.place_id}/index.json")
    fetch_osm = needed("osm", f"{park.place_id}.json")

    with http.client() as session:
        boundary_features: list[dict[str, Any]] | None = None

        if fetch_boundaries:
            print(f"    NPS boundaries for {park.unit_code}, and all 63 parks' outlines")
            directory = rawstore.version_directory("boundaries", version)
            record = FetchRecord(source=NPS_BOUNDARY_TERMS, fetched_at=rawstore.utc_now())
            boundary_features = arcgis.boundary_for_unit(session, park.unit_code, record=record)
            _write_geojson(
                directory / f"{park.place_id}.geojson", boundary_features, record, directory
            )
            national = arcgis.national_park_boundaries(session, record=record)
            _write_geojson(directory / "national-parks.geojson", national, record, directory)
            codes = {(f.get("properties") or {}).get("UNIT_CODE") for f in national}
            print(f"    {len(national)} boundary rows across {len(codes)} park codes")
            record.write(directory)

        if fetch_trails:
            print(f"    NPS Public Trails for {park.unit_code}")
            directory = rawstore.version_directory("trails", version)
            record = FetchRecord(source=NPS_TRAILS_TERMS, fetched_at=rawstore.utc_now())
            features = arcgis.trails_for_unit(session, park.unit_code, record=record)
            _write_geojson(directory / f"{park.place_id}.geojson", features, record, directory)
            print(f"    {len(features)} trail segments")
            record.write(directory)

        if fetch_elevation or fetch_osm:
            box = _render_box(park, boundary_features)

        if fetch_elevation:
            resolution = config.DEFAULT_PACK_SETTINGS.elevation_resolution_m
            print(f"    USGS 3DEP for {park.unit_code} at {resolution:.0f} m ground resolution")
            directory = rawstore.version_directory("elevation", version) / park.place_id
            directory.mkdir(parents=True, exist_ok=True)
            record = FetchRecord(
                source=SourceTerms(**threedep.TERMS), fetched_at=rawstore.utc_now()
            )
            index = threedep.download(session, directory, box, resolution, record=record)
            print(f"    {index['columns']}×{index['rows']} px elevation grid")
            record.write(directory.parent)

        if fetch_osm:
            print("    OpenStreetMap roads and water, via Overpass")
            directory = rawstore.version_directory("osm", version)
            record = FetchRecord(source=SourceTerms(**osm.TERMS), fetched_at=rawstore.utc_now())
            payload = osm.download(session, box, record=record)
            path = directory / f"{park.place_id}.json"
            path.write_text(json.dumps(payload))
            record.add_file(path, root=directory)
            print(f"    {len(payload.get('elements', []))} OSM elements")
            record.write(directory)

    if source is None:
        for name, reason in KEYED_SOURCES.items():
            print(f"    skipped {name}: {reason}")


def match() -> None:
    """Give every place, sight and trail a stable Unigrids ID.

    The mapping from source keys (NPS park code, PAD-US unit id) to Unigrids IDs is
    **persisted**, not recomputed: user logs point at these IDs, so an ID that changes
    silently orphans someone's visit. See ``ids.py``.
    """
    raise StepNotBuiltError(
        "match() is not built. It must assign stable Unigrids IDs, persist the mapping "
        "from NPS park codes and PAD-US unit IDs, and fail loudly when a previously "
        "issued ID would change. Until it exists, `derive` computes trail IDs from "
        "`ids.trail_id` each run, which is stable for a stable trail name but is not the "
        "persisted mapping the contract calls for."
    )


def derive(*, park_code: str = config.DEFAULT_PARK) -> None:
    """Compute everything the sources do not publish directly.

    Trail length, elevation gain and loss, and the elevation profile, all measured the
    same way from the route line and USGS elevation so no trail's numbers depend on who
    published them. Plus theme tags, the passport region for every site, monthly climate
    normals, and sight rankings.

    Built: the trail measurements, for one park, in ``work/<place>/trails.json``. The
    method is in ``measure.py`` and is recorded next to its output. Theme tags, passport
    regions, climate normals and sight ranks are not built — they need the NPS API and the
    full unit list, which need a key.
    """
    park = config.park(park_code)
    trail_features = _read_geojson(
        rawstore.require("trails", f"{park.place_id}.geojson") / f"{park.place_id}.geojson"
    )
    grid = dem.ElevationGrid.load(
        rawstore.require("elevation", f"{park.place_id}/index.json") / park.place_id
    )

    derived = trails.derive_trails(
        trail_features,
        place_id=park.place_id,
        place_slug=park.slug,
        sample_elevation=grid.sample,
    )
    measured = [trail for trail in derived if trail.gainMetres is not None]
    directory = config.WORK_DIR / park.place_id
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "trails.json").write_text(
        json.dumps(
            {
                "placeID": park.place_id,
                "unitCode": park.unit_code,
                "measurement": trails.measurement_method(),
                "trails": [trail.as_json() for trail in derived],
            },
            indent=1,
        )
        + "\n"
    )

    total_km = sum(trail.lengthMetres for trail in derived) / 1000.0
    print(
        f"    {len(derived)} trails, {len(measured)} with elevation, "
        f"{total_km:.1f} km of trail"
    )
    for trail in sorted(derived, key=lambda item: -item.lengthMetres)[:8]:
        gain = f"{trail.gainMetres:,.0f} m up" if trail.gainMetres is not None else "no elevation"
        print(f"      {trail.name:<36} {trail.lengthMetres / 1000:>6.2f} km  {gain}")
    print(
        "    not derived yet: theme tags, passport regions, climate normals, sight ranks, "
        "trail difficulty and route type"
    )


def edit() -> None:
    """Validate the curated, hand-written content in ``content/``.

    Guide text, permit and timed-entry rules, and seasonal notes are prose kept under
    version control. This step checks they parse, that every ID they reference resolves,
    and that every guide cites a source.
    """
    raise StepNotBuiltError(
        f"edit() is not built. It must validate the curated files in {config.CONTENT_DIR} "
        "against the matched dataset and reject dangling IDs or uncited guides."
    )


def build(
    *,
    park_code: str = config.DEFAULT_PARK,
    settings: config.PackSettings | None = None,
    skip_report: bool = False,
) -> packs.PackResult:
    """Write the bundled dataset and one offline pack per national park.

    The dataset becomes read-only SQLite (§3, §13); the packs are topo tiles rendered
    from 3DEP and OpenStreetMap, plus trails, sights and guide content for the park
    extent.

    **The pack size is the pilot's whole question.** Build Zion first, measure it, and
    report whether 63 parks plus the curated state parks fit inside the App Store's 4 GB
    limit (§16, ``docs/mvp-scope.md``).

    Built: one park's pack, and the size report that answers the question. The bundled
    SQLite dataset is not — it needs ``match`` and ``edit``, which need the NPS API.
    """
    park = config.park(park_code)
    settings = settings or config.DEFAULT_PACK_SETTINGS

    boundary_directory = rawstore.require("boundaries", f"{park.place_id}.geojson")
    trails_directory = rawstore.require("trails", f"{park.place_id}.geojson")
    elevation_directory = rawstore.require("elevation", f"{park.place_id}/index.json")
    osm_directory = rawstore.require("osm", f"{park.place_id}.json")

    boundary_features = _read_geojson(boundary_directory / f"{park.place_id}.geojson")
    trail_features = _read_geojson(trails_directory / f"{park.place_id}.geojson")
    osm_payload = json.loads((osm_directory / f"{park.place_id}.json").read_text())
    osm_ways = osm.ways(osm_payload)
    grid = dem.ElevationGrid.load(elevation_directory / park.place_id)
    print(
        f"    {len(trail_features)} trail segments, {len(osm_ways)} OSM ways, "
        f"{grid.columns}×{grid.rows} elevation grid ({grid.coverage:.1%} covered)"
    )

    sources = [
        _source_entry(boundary_directory),
        _source_entry(trails_directory),
        _source_entry(elevation_directory),
        _source_entry(osm_directory),
    ]

    result = packs.build(
        park,
        boundary_features=boundary_features,
        trail_features=trail_features,
        osm_ways=osm_ways,
        grid=grid,
        settings=settings,
        sources=[entry for entry in sources if entry],
        out_directory=config.OUT_DIR / "packs",
    )
    print(
        f"    pack: {result.total_bytes / 1e6:.2f} MB for {result.area_km2:,.0f} km² "
        f"({result.bytes_per_km2() / 1e3:.1f} KB/km²)"
    )

    if skip_report:
        return result

    national_path = boundary_directory / "national-parks.geojson"
    if not national_path.exists():
        print(
            "    no national-parks.geojson in the raw store, so the extrapolation is "
            "skipped. Run `unigrids-pipeline fetch --source boundaries`."
        )
        return result

    print("    counting tiles for every national park")
    estimates = sizereport.park_estimates(_read_geojson(national_path), settings)
    scenario_list = sizereport.scenarios(result, estimates)
    non_tile_bytes = result.total_bytes - result.mbtiles_bytes
    report_data = sizereport.report(
        result, estimates, scenario_list, non_tile_bytes_per_park=non_tile_bytes
    )
    json_path, markdown_path = sizereport.write(report_data, config.OUT_DIR)
    print(f"    {len(estimates)} parks counted; report written to {markdown_path}")
    for row in report_data["extrapolation"]["budget"]:
        if row["brochureAllowanceMegabytesPerPark"] == 0:
            print(
                f"      {row['scenario']:<16} {row['totalGigabytes']:>6.2f} GB  "
                f"{'fits' if row['fits'] else 'over'} 4 GB"
            )
    print(f"    machine-readable: {json_path}")
    return result


def package() -> None:
    """Copy the dataset and packs into the app's resources, and re-check brochure links.

    NPS brochure URLs are not standardised across parks and they move, so every stored
    link is re-checked here and a broken one is recorded so the viewer can fall back to
    the park's NPS maps page (§6, §12).
    """
    raise StepNotBuiltError(
        f"package() is not built. It must copy the built dataset into "
        f"{config.APP_RESOURCES} and re-verify every brochure link. The packs in "
        f"{config.OUT_DIR / 'packs'} are not copied into the app yet: the app has no "
        "tile-overlay screen to read them (docs/mvp-scope.md, 1.0.0)."
    )


def _render_box(park: config.Park, boundary_features: list[dict[str, Any]] | None) -> BoundingBox:
    """The extent elevation and OSM are fetched for: the park, buffered.

    Fetched a little wider than the pack renders, so a change to the buffer does not mean
    downloading 3DEP again.
    """
    if boundary_features is None:
        directory = rawstore.require("boundaries", f"{park.place_id}.geojson")
        boundary_features = _read_geojson(directory / f"{park.place_id}.geojson")
    rings = coverage.rings(boundary_features)
    if not rings:
        raise SystemExit(f"no boundary polygon found for {park.unit_code}")
    box = BoundingBox.around(
        point for ring in rings if not ring.is_hole for point in ring.coordinates
    )
    return box.buffered(config.DEFAULT_PACK_SETTINGS.boundary_buffer_m * 1.5)


def _write_geojson(
    path: Path, features: list[dict[str, Any]], record: FetchRecord, root: Path
) -> None:
    path.write_text(json.dumps(arcgis.feature_collection(features)))
    record.add_file(path, root=root)


def _read_geojson(path: Path) -> list[dict[str, Any]]:
    payload = json.loads(path.read_text())
    return payload.get("features") or []


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


ALL_STEPS = (fetch, match, derive, edit, build, package)
