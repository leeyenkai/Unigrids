"""The 4 GB question.

``SPECIFICATION.md`` §16 calls the pilot the riskiest step, and this is the risk: "how
large an offline pack really is, and so whether everything fits in the 4 GB app limit".
The answer has to be a calculation with its assumptions visible, because every number
downstream of it — how many zoom levels, which parks get packs, whether state parks get
packs at all — is a decision somebody makes on the strength of it.

So the model is explicit, and separates what is measured from what is assumed:

* **Measured, from Zion**: bytes per tile at each zoom, in each candidate format.
* **Computed, for all 63 parks**: how many tiles each park's real boundary needs, counted
  exactly as Zion's was.
* **Assumed, and stated**: that other parks' terrain compresses like Zion's. Zion is a
  canyon park with high-frequency relief, so this errs high.

Everything that is not a pack — the app binary, the reference database, the brochure
PDFs — is a line item with a stated figure rather than a silent omission, because a budget
that only counts the part already measured always fits.
"""

from __future__ import annotations

import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from . import config, coverage
from .coverage import ParkCoverage
from .geo import tile_resolution_m_per_pixel
from .packs import FORMATS, PackResult

# A latitude for the geometric state-park model. Mid-latitude continental US: a tile covers
# less ground further north, so a park modelled here is modelled slightly optimistically
# for Minnesota and pessimistically for Florida.
MODEL_LATITUDE = 39.0

BROCHURE_ALLOWANCES_MB = (0, 4, 12)
"""Per-park brochure PDF sizes the budget is shown against. Not measured: §6's brochure
links are not standardised and the ``package`` step is the one that resolves them, so the
budget shows the shape of the cost rather than claiming a figure."""


@dataclass
class ParkEstimate:
    """One park's tile cost.

    ``area_km2`` is the area of the NPS boundary polygon, which for several parks is the
    legislative boundary rather than the federal acreage — Wrangell–St. Elias encloses
    62,000 km² here against 53,000 km² of federal land. That is the right quantity for
    this purpose: a pack covers the mapped extent, not the ownership.
    """

    unit_code: str
    name: str
    area_km2: float
    tiles_by_zoom: dict[int, int]

    def tiles(self, zooms: list[int]) -> int:
        return sum(self.tiles_by_zoom.get(zoom, 0) for zoom in zooms)

    def bytes_for(self, zooms: list[int], mean_tile_bytes: dict[int, float]) -> float:
        return sum(
            self.tiles_by_zoom.get(zoom, 0) * mean_tile_bytes.get(zoom, 0.0) for zoom in zooms
        )


@dataclass(frozen=True)
class ZoomPolicy:
    """How deep a park's tiles go.

    A flat policy gives every park the same zooms. A tiered one gives the deepest zooms
    only to parks small enough to deserve them, which is the shape the measurement pushes
    towards: six Alaskan park-and-preserve units hold three quarters of the national tile
    count, and 2 m-per-pixel relief over a thousand square miles of trailless icefield is
    not a thing anyone will look at.
    """

    name: str
    min_zoom: int
    max_zoom: int
    area_tiers: tuple[tuple[float, int], ...] = ()
    """``(area ceiling in km², deepest zoom)``, smallest ceiling first. Empty means flat."""

    def zooms_for(self, area_km2: float) -> list[int]:
        deepest = self.max_zoom
        for ceiling, zoom in self.area_tiers:
            if area_km2 <= ceiling:
                deepest = min(zoom, self.max_zoom)
                break
        else:
            if self.area_tiers:
                deepest = min(self.area_tiers[-1][1], self.max_zoom)
        return list(range(self.min_zoom, deepest + 1))


@dataclass
class Scenario:
    """One zoom policy and tile format, costed over all 63 parks."""

    policy: ZoomPolicy
    tile_format: str
    national_tiles: int
    national_bytes: float
    per_park_bytes: float
    bytes_per_state_park_km2: dict[int, float]

    @property
    def name(self) -> str:
        return f"{self.policy.name}, {self.tile_format}"

    def as_json(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "zoomPolicy": self.policy.name,
            "minZoom": self.policy.min_zoom,
            "maxZoom": self.policy.max_zoom,
            "areaTiers": [
                {"uptoSquareKilometres": ceiling, "maxZoom": zoom}
                for ceiling, zoom in self.policy.area_tiers
            ],
            "tileFormat": self.tile_format,
            "nationalParkTiles": self.national_tiles,
            "nationalParkBytes": round(self.national_bytes),
            "nationalParkGigabytes": round(self.national_bytes / 1e9, 3),
            "meanBytesPerPark": round(self.per_park_bytes),
            "bytesPerStateParkOfArea": {
                str(area): round(value) for area, value in self.bytes_per_state_park_km2.items()
            },
        }


def park_estimates(
    boundary_features: list[dict[str, Any]], settings: config.PackSettings
) -> list[ParkEstimate]:
    """Tile counts for every national park, from its own boundary.

    A park and preserve arrives as several boundary rows under one park code; they are
    counted together, because one pack covers the unit a visitor calls by that name.
    """
    by_code: dict[str, list[dict[str, Any]]] = {}
    names: dict[str, str] = {}
    for feature in boundary_features:
        properties = feature.get("properties") or {}
        code = properties.get("UNIT_CODE")
        if not code:
            continue
        by_code.setdefault(code, []).append(feature)
        name = properties.get("PARKNAME") or properties.get("UNIT_NAME") or code
        # A park and preserve is two rows; name it after the park half, not the preserve.
        if code not in names or properties.get("UNIT_TYPE") == "National Parks":
            names[code] = name

    zooms = list(range(settings.min_zoom, settings.max_zoom + 1))
    estimates: list[ParkEstimate] = []
    for code, features in sorted(by_code.items()):
        rings = coverage.rings(features)
        if not rings:
            continue
        park_coverage = ParkCoverage(
            rings, buffer_m=settings.boundary_buffer_m, max_zoom=settings.max_zoom
        )
        estimates.append(
            ParkEstimate(
                unit_code=code,
                name=names[code],
                area_km2=park_coverage.area_km2,
                tiles_by_zoom=park_coverage.tile_counts(zooms),
            )
        )
    return estimates


def modelled_tiles(area_km2: float, zoom: int, settings: config.PackSettings) -> int:
    """Tiles for a park of a given area, modelled as a square plus the buffer.

    Used for the state parks, because which ones get packs has not been decided
    (``SPECIFICATION.md`` §17, follow-up 1). A square is the shape that costs least per
    unit of area, so this is a floor rather than a forecast — and for a small park the
    buffer dominates, which the shape of the numbers makes clear.
    """
    side_m = math.sqrt(max(area_km2, 0.0) * 1e6) + 2.0 * settings.boundary_buffer_m
    tile_ground_m = tile_resolution_m_per_pixel(zoom, MODEL_LATITUDE, settings.tile_size) * (
        settings.tile_size
    )
    across = max(1, math.ceil(side_m / tile_ground_m) + 1)
    return across * across


def policies(settings: config.PackSettings) -> list[ZoomPolicy]:
    """The zoom policies worth costing, including the one that actually fits."""
    deepest = settings.max_zoom
    shallowest = settings.min_zoom
    return [
        ZoomPolicy(f"z{shallowest}–{deepest}", shallowest, deepest),
        ZoomPolicy(f"z{shallowest}–{deepest - 1}", shallowest, deepest - 1),
        ZoomPolicy(f"z{shallowest}–{deepest - 2}", shallowest, deepest - 2),
        ZoomPolicy(
            "tiered by area",
            shallowest,
            deepest,
            area_tiers=((2_000.0, deepest), (10_000.0, deepest - 1), (float("inf"), deepest - 2)),
        ),
        ZoomPolicy(
            "tiered, wilderness shallow",
            shallowest,
            deepest,
            area_tiers=((2_000.0, deepest), (10_000.0, deepest - 1), (float("inf"), deepest - 3)),
        ),
    ]


def scenarios(
    pack: PackResult,
    estimates: list[ParkEstimate],
    *,
    zoom_policies: list[ZoomPolicy] | None = None,
    state_park_areas: tuple[int, ...] = (10, 25, 50, 100),
) -> list[Scenario]:
    """Cost every combination of zoom policy and tile format."""
    settings = pack.settings
    chosen = zoom_policies or policies(settings)
    results: list[Scenario] = []
    for tile_format in FORMATS:
        mean_bytes = pack.mean_tile_bytes(tile_format)
        for policy in chosen:
            total_bytes = 0.0
            total_tiles = 0
            for estimate in estimates:
                zooms = policy.zooms_for(estimate.area_km2)
                total_bytes += estimate.bytes_for(zooms, mean_bytes)
                total_tiles += estimate.tiles(zooms)
            # A state park is costed at the policy's deepest zooms, since every state park
            # on a curated list is small enough to sit in the smallest tier.
            state_zooms = policy.zooms_for(0.0)
            results.append(
                Scenario(
                    policy=policy,
                    tile_format=tile_format,
                    national_tiles=total_tiles,
                    national_bytes=total_bytes,
                    per_park_bytes=total_bytes / len(estimates) if estimates else 0.0,
                    bytes_per_state_park_km2={
                        area: sum(
                            modelled_tiles(area, zoom, settings) * mean_bytes.get(zoom, 0.0)
                            for zoom in state_zooms
                        )
                        for area in state_park_areas
                    },
                )
            )
    return results


def report(
    pack: PackResult,
    estimates: list[ParkEstimate],
    scenario_list: list[Scenario],
    *,
    non_tile_bytes_per_park: int,
) -> dict[str, Any]:
    """The whole measurement, as the structure the Markdown is rendered from."""
    measured = {
        "park": pack.park.name,
        "placeID": pack.park.place_id,
        "areaSquareKilometres": round(pack.area_km2, 1),
        "settings": {
            "minZoom": pack.settings.min_zoom,
            "maxZoom": pack.settings.max_zoom,
            "tileSize": pack.settings.tile_size,
            "tileFormat": pack.settings.tile_format,
            "boundaryBufferMetres": pack.settings.boundary_buffer_m,
            "elevationResolutionMetres": pack.settings.elevation_resolution_m,
        },
        "files": pack.files,
        "totalBytes": pack.total_bytes,
        "totalMegabytes": round(pack.total_bytes / 1e6, 2),
        "tileBytes": pack.tile_bytes,
        "mbtilesBytes": pack.mbtiles_bytes,
        "sqliteOverheadBytes": pack.mbtiles_bytes - pack.tile_bytes,
        "bytesPerSquareKilometre": round(pack.bytes_per_km2()),
        "byZoom": [zoom.as_json() for zoom in pack.zooms],
        "trails": {
            "count": pack.trail_count,
            "measured": pack.measured_trail_count,
            "totalLengthKilometres": round(pack.trail_length_km, 2),
            "elevationCoverage": round(pack.elevation_coverage, 4),
        },
        "vectors": pack.vector_counts,
        "sources": pack.sources,
    }

    budget = []
    for brochure_mb in BROCHURE_ALLOWANCES_MB:
        for scenario in scenario_list:
            packs_bytes = scenario.national_bytes + non_tile_bytes_per_park * len(estimates)
            brochures = brochure_mb * 1_000_000 * len(estimates)
            total = packs_bytes + brochures
            budget.append(
                {
                    "scenario": scenario.name,
                    "brochureAllowanceMegabytesPerPark": brochure_mb,
                    "nationalPackGigabytes": round(packs_bytes / 1e9, 3),
                    "brochureGigabytes": round(brochures / 1e9, 3),
                    "totalGigabytes": round(total / 1e9, 3),
                    "headroomGigabytes": round(
                        (config.APP_STORE_LIMIT_BYTES - total) / 1e9, 3
                    ),
                    "fits": total < config.APP_STORE_LIMIT_BYTES,
                }
            )

    return {
        "measured": measured,
        "extrapolation": {
            "parkCount": len(estimates),
            "assumption": (
                "Tile counts are each park's own buffered boundary, counted as Zion's "
                "were. Bytes per tile are Zion's, which is dense canyon terrain and so "
                "errs high for prairie and plateau parks."
            ),
            "appStoreLimitBytes": config.APP_STORE_LIMIT_BYTES,
            "nonTileBytesPerPark": non_tile_bytes_per_park,
            "parks": [
                {
                    "unitCode": estimate.unit_code,
                    "name": estimate.name,
                    "areaSquareKilometres": round(estimate.area_km2, 1),
                    "tilesByZoom": {
                        str(zoom): count for zoom, count in estimate.tiles_by_zoom.items()
                    },
                }
                for estimate in sorted(estimates, key=lambda item: -item.area_km2)
            ],
            "scenarios": [scenario.as_json() for scenario in scenario_list],
            "budget": budget,
        },
    }


def write(report_data: dict[str, Any], directory: Path) -> tuple[Path, Path]:
    json_path = directory / "pack-size-report.json"
    json_path.write_text(json.dumps(report_data, indent=2) + "\n")
    markdown_path = directory / "pack-size-report.md"
    markdown_path.write_text(markdown(report_data))
    return json_path, markdown_path


def markdown(report_data: dict[str, Any]) -> str:
    measured = report_data["measured"]
    extrapolation = report_data["extrapolation"]
    settings = measured["settings"]

    lines = [
        f"# Offline pack size — {measured['park']}",
        "",
        f"Measured pack: **{measured['totalMegabytes']} MB** for "
        f"{measured['areaSquareKilometres']} km² of park, zoom "
        f"{settings['minZoom']}–{settings['maxZoom']}, {settings['tileSize']} px "
        f"{settings['tileFormat']} tiles, "
        f"{settings['boundaryBufferMetres']:.0f} m boundary buffer.",
        "",
        "## By zoom level",
        "",
        "| Zoom | m/px | Tiles | Bounding box would be | MB | KB/tile |",
        "|---:|---:|---:|---:|---:|---:|",
    ]
    for zoom in measured["byZoom"]:
        lines.append(
            f"| {zoom['zoom']} | {zoom['metresPerPixel']:.2f} | {zoom['tiles']:,} | "
            f"{zoom['boundingBoxTiles']:,} | {zoom['bytes'] / 1e6:.2f} | "
            f"{zoom['meanTileBytes'] / 1024:.1f} |"
        )
    total_tiles = sum(zoom["tiles"] for zoom in measured["byZoom"])
    lines += [
        f"| **total** | | **{total_tiles:,}** | "
        f"**{sum(z['boundingBoxTiles'] for z in measured['byZoom']):,}** | "
        f"**{measured['tileBytes'] / 1e6:.2f}** | |",
        "",
        "## Files in the pack",
        "",
        "| File | Bytes |",
        "|---|---:|",
    ]
    for name, size in measured["files"].items():
        lines.append(f"| `{name}` | {size:,} |")
    lines += [
        f"| **total** | **{measured['totalBytes']:,}** |",
        "",
        f"SQLite overhead above the raw tile bytes: "
        f"{measured['sqliteOverheadBytes'] / 1e6:.2f} MB.",
        "",
        "## Tile format, measured on the same tiles",
        "",
        "| Zoom | " + " | ".join(f"{fmt} KB/tile" for fmt in FORMATS) + " |",
        "|---:|" + "---:|" * len(FORMATS),
    ]
    for zoom in measured["byZoom"]:
        sample = zoom.get("sampleMeanTileBytes") or {}
        cells = [f"{sample.get(fmt, 0) / 1024:.1f}" for fmt in FORMATS]
        lines.append(f"| {zoom['zoom']} | " + " | ".join(cells) + " |")

    lines += [
        "",
        f"## All {extrapolation['parkCount']} national parks",
        "",
        extrapolation["assumption"],
        "",
        "| Scenario | Tiles | Packs (GB) | Mean per park (MB) | A 25 km² state park (MB) |",
        "|---|---:|---:|---:|---:|",
    ]
    for scenario in extrapolation["scenarios"]:
        state = scenario["bytesPerStateParkOfArea"].get("25", 0)
        lines.append(
            f"| {scenario['name']} | {scenario['nationalParkTiles']:,} | "
            f"{scenario['nationalParkGigabytes']:.2f} | "
            f"{scenario['meanBytesPerPark'] / 1e6:.1f} | {state / 1e6:.1f} |"
        )

    lines += [
        "",
        "## Against the 4 GB limit",
        "",
        f"The pack's own format, {measured['settings']['tileFormat']}, against three "
        "per-park brochure PDF allowances. Every other combination, PNG included, is in "
        "the JSON beside this file.",
        "",
        "| Scenario | Brochure MB/park | Packs GB | Brochures GB | Total GB | Headroom GB | Fits |",
        "|---|---:|---:|---:|---:|---:|:--:|",
    ]
    for row in extrapolation["budget"]:
        if not row["scenario"].endswith(measured["settings"]["tileFormat"]):
            continue
        lines.append(
            f"| {row['scenario']} | {row['brochureAllowanceMegabytesPerPark']} | "
            f"{row['nationalPackGigabytes']:.2f} | {row['brochureGigabytes']:.2f} | "
            f"{row['totalGigabytes']:.2f} | {row['headroomGigabytes']:.2f} | "
            f"{'yes' if row['fits'] else 'no'} |"
        )

    lines += [
        "",
        "The app binary, the reference database and the app's own assets are not in these",
        "totals. Nor is iOS's own app-thinning, which reduces what a given device",
        "downloads but not the 4 GB the uncompressed bundle is measured against.",
        "",
        "## Where the tiles are",
        "",
        "Six park-and-preserve units in Alaska, plus Death Valley, hold most of the",
        "national tile count — and they are the places a 2-metre-per-pixel tile is least",
        "use, being roadless wilderness with no trail network to draw on it. That is what",
        "the tiered policies trade away, and why they cost so much less than trimming a",
        "zoom level off every park alike.",
        "",
        "| Park | km² | Tiles at full depth |",
        "|---|---:|---:|",
    ]
    for park in extrapolation["parks"][:10]:
        lines.append(
            f"| {park['name']} | {park['areaSquareKilometres']:,.0f} | "
            f"{sum(park['tilesByZoom'].values()):,} |"
        )
    lines.append("")
    return "\n".join(lines)
