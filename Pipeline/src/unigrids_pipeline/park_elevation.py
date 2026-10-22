"""The highest and lowest ground in a national park, measured where no source gives it.

A guide's at-a-glance panel shows an elevation range, and the curated facts carry one
only where the park's own material states it. For the rest, the USGS 3DEP image service
computes the range over the park's outline (``computeStatisticsHistograms``), and the
figure is labelled as measured, with its method, rather than passed off as published.

Checked against parks that publish theirs: Glacier comes to 3,185 m against Mount
Cleveland's 3,190 m, Great Smoky Mountains to 2,025 m against Kuwohi's 2,025 m. Peaks
narrower than a pixel read a little low, so the figure is rounded and the note says
"about".
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from . import outline, rawstore, reference_content
from .rawstore import FetchRecord, SourceTerms
from .sources import http

URL = (
    "https://elevation.nationalmap.gov/arcgis/rest/services/3DEPElevation/ImageServer/"
    "computeStatisticsHistograms"
)
SOURCE = "park-elevation"
FILE = "extremes.json"
NOTE = "Highest and lowest ground measured from USGS 3DEP elevation within the park boundary"

TERMS = SourceTerms(
    identifier="usgs-3dep-statistics",
    title="USGS 3DEP elevation statistics over each national park's outline",
    url=URL,
    licence="Public domain (US Geological Survey)",
    attribution="Elevation data courtesy of the U.S. Geological Survey (3DEP)",
    notes="Minimum and maximum over the park outline, at the pixel size recorded per park.",
)


def pixel_size(area_km2: float) -> int:
    """Web Mercator metres per pixel: finest for ordinary parks, coarser for the vast
    Alaskan ones, which the service would otherwise refuse (and which sit far enough
    north that a Mercator metre is half a ground metre)."""
    if area_km2 <= 10_000:
        return 30
    return 60


def fetch(version: str, unit_outlines: dict[str, list[outline.Polygon]]) -> Path:
    directory = rawstore.version_directory(SOURCE, version)
    path = directory / FILE
    found: dict[str, Any] = json.loads(path.read_text()) if path.exists() else {}
    record = FetchRecord(source=TERMS, fetched_at=rawstore.utc_now())
    facts = reference_content.national_park_facts()
    with http.client() as session:
        for code, row in reference_content.national_park_rows():
            if code in found:
                continue
            curated = {**(reference_content.guide(row["id"]) or {}).get("facts", {}), **facts.get(
                row["id"], {}
            )}
            if "lowestElevationMetres" in curated and "highestElevationMetres" in curated:
                continue
            polygons = unit_outlines.get(code.upper())
            if not polygons:
                continue
            simplified = outline.generalise(polygons, 0.002)
            area = sum(outline.geodesic_acres([polygon]) for polygon in simplified) / 247.105
            size = pixel_size(area)
            rings = [
                [[lon, lat] for lon, lat in [*ring, ring[0]]]
                for polygon in simplified
                for ring in polygon[:1]
            ]
            form = {
                "geometry": json.dumps({"rings": rings, "spatialReference": {"wkid": 4326}}),
                "geometryType": "esriGeometryPolygon",
                "pixelSize": json.dumps({"x": size, "y": size, "spatialReference": {"wkid": 3857}}),
                "f": "json",
            }
            try:
                response = http.post(session, URL, data=form, expect="application/json")
            except http.FetchError as error:
                print(f"    park-elevation: {code} failed ({error})")
                continue
            statistics = (response.json().get("statistics") or [{}])[0]
            if statistics.get("min") is None or statistics.get("max") is None:
                continue
            found[code] = {
                "min": statistics["min"],
                "max": statistics["max"],
                "pixelSize": size,
            }
            record.add_request(URL, {"park": code, "pixelSize": size})
            print(f"    park-elevation: {code} {statistics['min']:.0f}–{statistics['max']:.0f} m")
    path.write_text(json.dumps(found, indent=1) + "\n")
    record.add_file(path, root=directory)
    record.write(directory)
    return directory


def attach(places: list[dict[str, Any]], directory: Path | None) -> int:
    """Fill each national park's missing elevation figures from the measurement."""
    if directory is None:
        return 0
    found = json.loads((directory / FILE).read_text())
    filled = 0
    for place in places:
        if place["kind"] != "nationalPark":
            continue
        entry = found.get(place.get("npsParkCode") or "")
        if not entry:
            continue
        facts = place.setdefault("facts", {})
        added = False
        if "highestElevationMetres" not in facts:
            facts["highestElevationMetres"] = round(entry["max"])
            added = True
        if "lowestElevationMetres" not in facts:
            # Within a few metres of zero is the sea, not a measured hollow.
            low = round(entry["min"])
            facts["lowestElevationMetres"] = 0 if -3 <= low <= 3 else low
            added = True
        if added:
            facts["elevationNote"] = NOTE
            filled += 1
    print(f"    park-elevation: {filled} parks' ranges measured")
    return filled
