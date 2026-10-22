"""Assembling an offline pack, and answering the question it exists to answer.

A pack is one directory per park: the tiles as MBTiles, the measured trails, a manifest
and the attribution the sources oblige it to carry. Building Zion's is the first half of
``docs/mvp-scope.md``'s last exit criterion; the second half is the number this module
reports.

The extrapolation deserves a word. It would be easy to multiply Zion's pack by 63 and call
that the answer, and it would be wrong in both directions: Zion is a tenth the size of
Yellowstone and a ninetieth the size of Wrangell–St. Elias, while a flat prairie park
compresses far better than a canyon. So the tile *count* is computed exactly — every
park's real boundary, buffered and counted the way Zion's was — and only the *bytes per
tile* are carried over from Zion, which is the quantity Zion is actually evidence for. Zion
is dense terrain, so that carry-over errs high, and the report says so.
"""

from __future__ import annotations

import json
import random
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from . import config, coverage, mbtiles, render, trails
from .coverage import ParkCoverage
from .dem import ElevationGrid
from .geo import BoundingBox, tile_resolution_m_per_pixel

FORMATS = ("png", "png8", "webp")
SAMPLE_TILES_PER_ZOOM = 48
"""How many tiles per zoom get encoded in every format, for the format comparison."""


@dataclass
class ZoomMeasurement:
    zoom: int
    tiles: int
    bytes_total: int
    bounding_box_tiles: int
    metres_per_pixel: float
    sample_bytes: dict[str, list[int]] = field(default_factory=dict)

    @property
    def mean_tile_bytes(self) -> float:
        return self.bytes_total / self.tiles if self.tiles else 0.0

    def mean_sample_bytes(self, tile_format: str) -> float:
        sample = self.sample_bytes.get(tile_format) or []
        return sum(sample) / len(sample) if sample else 0.0

    def as_json(self) -> dict[str, Any]:
        return {
            "zoom": self.zoom,
            "tiles": self.tiles,
            "bytes": self.bytes_total,
            "meanTileBytes": round(self.mean_tile_bytes, 1),
            "metresPerPixel": round(self.metres_per_pixel, 2),
            "boundingBoxTiles": self.bounding_box_tiles,
            "tilesSavedByClipping": self.bounding_box_tiles - self.tiles,
            "sampleMeanTileBytes": {
                tile_format: round(self.mean_sample_bytes(tile_format), 1)
                for tile_format in FORMATS
                if self.sample_bytes.get(tile_format)
            },
        }


@dataclass
class PackResult:
    """A built pack and everything measured while building it."""

    park: config.Park
    directory: Path
    settings: config.PackSettings
    bounds: BoundingBox
    render_bounds: BoundingBox
    area_km2: float
    zooms: list[ZoomMeasurement]
    files: dict[str, int]
    trail_count: int
    measured_trail_count: int
    trail_length_km: float
    elevation_coverage: float
    vector_counts: dict[str, int]
    sources: list[dict[str, str]]
    tile_bytes: int
    mbtiles_bytes: int

    @property
    def total_bytes(self) -> int:
        return sum(self.files.values())

    def bytes_per_km2(self) -> float:
        return self.total_bytes / self.area_km2 if self.area_km2 else 0.0

    def mean_tile_bytes(self, tile_format: str) -> dict[int, float]:
        """Mean bytes per tile at each zoom, for one format.

        The pack's own format is measured over every tile; the others over the sample.
        """
        means: dict[int, float] = {}
        for zoom in self.zooms:
            if tile_format == self.settings.tile_format:
                means[zoom.zoom] = zoom.mean_tile_bytes
            else:
                means[zoom.zoom] = zoom.mean_sample_bytes(tile_format) or zoom.mean_tile_bytes
        return means


def build(
    park: config.Park,
    *,
    boundary_features: list[dict[str, Any]],
    trail_features: list[dict[str, Any]],
    osm_ways: list[dict[str, Any]],
    grid: ElevationGrid,
    settings: config.PackSettings,
    sources: list[dict[str, str]],
    out_directory: Path,
) -> PackResult:
    """Render and write one park's pack."""
    boundary_rings = coverage.rings(boundary_features)
    trail_box = _box_of_trails(trail_features)
    park_coverage = ParkCoverage(
        boundary_rings,
        buffer_m=settings.boundary_buffer_m,
        max_zoom=settings.max_zoom,
        extra=trail_box,
    )
    zooms = list(range(settings.min_zoom, settings.max_zoom + 1))

    directory = out_directory / park.place_id
    directory.mkdir(parents=True, exist_ok=True)

    derived = trails.derive_trails(
        trail_features,
        place_id=park.place_id,
        place_slug=park.slug,
        sample_elevation=grid.sample,
    )
    measured = [trail for trail in derived if trail.gainMetres is not None]
    trails_path = directory / "trails.json"
    trails_path.write_text(
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

    layers = render.layers_from_sources(osm_ways, trail_features, boundary_features)
    renderer = render.TileRenderer(grid, layers, tile_size=settings.tile_size)

    measurements: list[ZoomMeasurement] = []
    bounding_box_counts = park_coverage.bounding_box_tile_counts(zooms)
    _, centre_latitude = park_coverage.render_bounds.centre

    with mbtiles.MBTilesWriter(directory / "tiles.mbtiles") as writer:
        for zoom in zooms:
            tiles = park_coverage.tiles(zoom)
            measurement = ZoomMeasurement(
                zoom=zoom,
                tiles=len(tiles),
                bytes_total=0,
                bounding_box_tiles=bounding_box_counts[zoom],
                metres_per_pixel=tile_resolution_m_per_pixel(
                    zoom, centre_latitude, settings.tile_size
                ),
            )
            sample_indices = _sample_indices(len(tiles), SAMPLE_TILES_PER_ZOOM, zoom)
            for index, (x, y) in enumerate(tiles):
                image = renderer.render(zoom, x, y)
                data = render.encode(
                    image, settings.tile_format, webp_quality=settings.webp_quality
                )
                writer.add(zoom, x, y, data)
                measurement.bytes_total += len(data)
                if index in sample_indices:
                    for tile_format in FORMATS:
                        encoded = (
                            data
                            if tile_format == settings.tile_format
                            else render.encode(
                                image, tile_format, webp_quality=settings.webp_quality
                            )
                        )
                        measurement.sample_bytes.setdefault(tile_format, []).append(len(encoded))
            measurements.append(measurement)
            layers.forget_index(zoom)
            print(
                f"    z{zoom:<2} {measurement.tiles:>6} tiles  "
                f"{measurement.bytes_total / 1e6:>8.2f} MB  "
                f"{measurement.mean_tile_bytes / 1024:>6.1f} KB/tile  "
                f"{measurement.metres_per_pixel:>8.2f} m/px"
            )
        writer.describe(
            name=f"{park.name} offline pack",
            description=(
                "Topo-style tiles rendered from USGS 3DEP elevation and OpenStreetMap "
                "roads and water, with NPS public trails. Not an NPS product."
            ),
            tile_format=settings.tile_format,
            bounds=park_coverage.render_bounds,
            min_zoom=settings.min_zoom,
            max_zoom=settings.max_zoom,
            attribution=(
                "Elevation: USGS 3DEP (public domain). Roads and water: "
                "© OpenStreetMap contributors (ODbL). Trails: NPS Public Trails."
            ),
        )
        tile_bytes = writer.tile_bytes

    total_length_m = sum(trail.lengthMetres for trail in derived)
    covered = sum(
        trail.elevationCoverage * trail.lengthMetres for trail in derived
    )

    _write_attribution(directory, park, sources, settings)
    _write_manifest(
        directory,
        park,
        settings,
        park_coverage,
        measurements,
        sources,
        trail_count=len(derived),
        measured_trail_count=len(measured),
        trail_length_km=total_length_m / 1000.0,
    )

    files = {
        path.name: path.stat().st_size for path in sorted(directory.iterdir()) if path.is_file()
    }
    return PackResult(
        park=park,
        directory=directory,
        settings=settings,
        bounds=park_coverage.bounds,
        render_bounds=park_coverage.render_bounds,
        area_km2=park_coverage.area_km2,
        zooms=measurements,
        files=files,
        trail_count=len(derived),
        measured_trail_count=len(measured),
        trail_length_km=total_length_m / 1000.0,
        elevation_coverage=covered / total_length_m if total_length_m else 0.0,
        vector_counts=layers.counts(),
        sources=sources,
        tile_bytes=tile_bytes,
        mbtiles_bytes=(directory / "tiles.mbtiles").stat().st_size,
    )


def _box_of_trails(trail_features: list[dict[str, Any]]) -> BoundingBox | None:
    """The trails' own extent, in case a trail runs outside the boundary buffer."""
    points: list[tuple[float, float]] = []
    for feature in trail_features:
        geometry = feature.get("geometry") or {}
        kind = geometry.get("type")
        lines = []
        if kind == "LineString":
            lines = [geometry.get("coordinates") or []]
        elif kind == "MultiLineString":
            lines = geometry.get("coordinates") or []
        for line in lines:
            points.extend((float(point[0]), float(point[1])) for point in line if len(point) >= 2)
    return BoundingBox.around(points) if points else None


def _sample_indices(total: int, wanted: int, seed: int) -> set[int]:
    """A fixed random sample of tile positions, so a rebuild measures the same tiles."""
    if total <= wanted:
        return set(range(total))
    return set(random.Random(seed).sample(range(total), wanted))


def _write_attribution(
    directory: Path,
    park: config.Park,
    sources: list[dict[str, str]],
    settings: config.PackSettings,
) -> None:
    """What the pack owes, written next to the bytes that owe it.

    The ODbL distinction matters enough to spell out: the tiles are a Produced Work, so
    they owe attribution; the trail geometry is NPS, not OSM, so nothing in this pack is a
    Derivative Database and share-alike is not engaged. If a later pass fills trail gaps
    from OSM ways — which ``SPECIFICATION.md`` §8 contemplates — that stops being true and
    this file has to change with it.
    """
    lines = [
        f"# Attribution — {park.name} offline pack",
        "",
        "This pack ships inside the Unigrids app. It is **not** a National Park Service",
        "product and implies no NPS affiliation or endorsement. It carries no NPS",
        "arrowhead and no NPS seal.",
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
        "## What this pack owes, and what it does not",
        "",
        "**Attribution, in the app.** The credits panel and the map's attribution control",
        "must name OpenStreetMap contributors, the USGS and the NPS trails dataset. The",
        "same strings are in `tiles.mbtiles`'s `attribution` metadata.",
        "",
        "**Share-alike: not engaged by this pack.** Under the ODbL a rendered tile is a",
        "Produced Work — an image made from the database rather than the database — so the",
        "tiles owe attribution and nothing more. No OpenStreetMap geometry is shipped as",
        "data here: the trail lines in `trails.json` come from the NPS Public Trails",
        "dataset and the elevation from 3DEP. The moment OSM ways are used to fill gaps in",
        "the trail catalogue, `trails.json` becomes a Derivative Database, share-alike",
        "applies to it, and that has to be handled before such a pack ships.",
        "",
        f"Rendered at zoom {settings.min_zoom}–{settings.max_zoom}, "
        f"{settings.tile_size} px tiles, {settings.tile_format}.",
        "",
    ]
    (directory / "ATTRIBUTION.md").write_text("\n".join(lines))


def _write_manifest(
    directory: Path,
    park: config.Park,
    settings: config.PackSettings,
    park_coverage: ParkCoverage,
    measurements: list[ZoomMeasurement],
    sources: list[dict[str, str]],
    *,
    trail_count: int,
    measured_trail_count: int,
    trail_length_km: float,
) -> None:
    from .rawstore import utc_now

    manifest = {
        "packVersion": 1,
        "placeID": park.place_id,
        "unitCode": park.unit_code,
        "name": park.name,
        "generatedAt": utc_now(),
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
        "trails": {
            "file": "trails.json",
            "count": trail_count,
            "measuredCount": measured_trail_count,
            "totalLengthKilometres": round(trail_length_km, 2),
        },
        "sources": sources,
        "notIncludedYet": [
            "sights and visitor centres (needs the NPS API, which needs a key)",
            "guide content (the edit step's curated files)",
            "the brochure PDF and its checked link (the package step)",
            "trail difficulty, route type, features and sights along the way",
        ],
        "attribution": "ATTRIBUTION.md",
    }
    (directory / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
