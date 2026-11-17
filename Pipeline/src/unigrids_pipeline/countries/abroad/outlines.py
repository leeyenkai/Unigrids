"""National park outlines abroad, read straight from each country's source.

A country's ``assemble`` hands its outlines to the trail catalogue itself. The pack steps
run without a reference build, so they read the outline sources directly:

* **Japan**: the Ministry of the Environment's zones (``nps.zip``,
  ``docs/sources-japan-norway.md`` J2), the snapshot the Japanese fetch keeps in
  ``raw/<date>/jp-biodic/``, or one taken here when there is none. A park is the union of
  its zones, joined by the park's Japanese name, as the Japanese build joins them.
* **Norway**: Miljødirektoratet's Naturvernområder service (N1, N2) in WGS84, the copy the
  Norwegian fetch keeps in ``raw/<date>/no-naturvern/``, or one asked for here.
* **New Zealand**: DOC's Public Conservation Land layer (CC BY 4.0), the national parks
  (Section ``S4_NATIONAL_PARK``) in WGS84, joined by ``NaPALIS_ID``: the copy the New
  Zealand fetch keeps in ``raw/<date>/nz-pcl/``, or one asked for here.

The country packages are read, never changed: Japan's Shapefile reader and union are
reused as they are.
"""

from __future__ import annotations

import json
from functools import cache
from pathlib import Path
from typing import Any

from ... import config, outline, rawstore
from ...rawstore import FetchRecord, SourceTerms
from ...sources import http

COUNTRIES = ("jp", "no", "nz")

NPS_ZIP_URL = "https://www.biodic.go.jp/shapedata/nps.zip"
NPS_ZIP = "nps.zip"
VERN_LAYER = "https://kart.miljodirektoratet.no/arcgis/rest/services/vern/MapServer/0"
NATIONAL_PARKS_WHERE = "verneform IN ('Nasjonalpark','NasjonalparkSvalbard')"
PCL_LAYER = (
    "https://services1.arcgis.com/3JjYDyG3oajxU6HO/ArcGIS/rest/services/"
    "DOC_Public_Conservation_Land_FHV/FeatureServer/0"
)
PCL_NATIONAL_PARKS_WHERE = "Section = 'S4_NATIONAL_PARK'"

SOURCES = {"jp": "abroad-outlines-jp", "no": "abroad-outlines-no", "nz": "abroad-outlines-nz"}
"""Where outlines this module fetched or derived are kept, one folder per country so each
carries its own terms."""

COUNTRY_SOURCES = {
    "jp": ("jp-biodic", NPS_ZIP),
    "no": ("no-naturvern", "national-parks.geojson"),
    "nz": ("nz-pcl", "national-parks.geojson"),
}
"""What the country packages' own fetches leave in the raw store, read first."""

TERMS = {
    "jp": SourceTerms(
        identifier="moe-biodic-nps",
        title="Ministry of the Environment Biodiversity Center: national park zones (nps.zip)",
        url=NPS_ZIP_URL,
        licence="Public Data License 1.0 (MOE Biodiversity Center terms of use)",
        attribution=(
            "出典：「国立公園区域等」（環境省生物多様性センター）"
            "https://www.biodic.go.jp/shapedata/nps.zip。Unigrids が簡略化・加工して作成"
        ),
        notes=(
            "Zones merged into one outline per park. MOE: 本データは、指定区域の概要を示すために"
            "作成したものであり、誤差を含みます — not a legal boundary."
        ),
    ),
    "no": SourceTerms(
        identifier="miljodirektoratet-naturvern",
        title="Miljødirektoratet, Naturvernområder: national parks",
        url=VERN_LAYER,
        licence="NLOD 2.0",
        attribution=(
            "Contains data under the Norwegian licence for Open Government data (NLOD) "
            "distributed by Miljødirektoratet"
        ),
        notes="Geometry in WGS84 (outSR 4326); a park split into several features is joined.",
    ),
    "nz": SourceTerms(
        identifier="doc-public-conservation-land",
        title="Department of Conservation, Public Conservation Land: national parks",
        url=PCL_LAYER,
        licence="CC BY 4.0",
        attribution="Crown Copyright: Department of Conservation Te Papa Atawhai",
        notes="Geometry in WGS84 (outSR 4326), joined to the park list by NaPALIS_ID.",
    ),
}


@cache
def park_list(country: str) -> tuple[dict[str, Any], ...]:
    """The country's national parks as its content list fixes them (``id``, ``name``…)."""
    if country not in COUNTRIES:
        raise ValueError(f"no parks abroad for {country!r}; known: {', '.join(COUNTRIES)}")
    path = config.CONTENT_DIR / "countries" / country / "national-parks.json"
    return tuple(json.loads(path.read_text())["parks"])


def country_of(place_id: str) -> str:
    country = place_id.split("-", 1)[0].lower()
    if country not in COUNTRIES:
        raise ValueError(f"{place_id!r} is not a park abroad")
    return country


def park(place_id: str) -> dict[str, Any]:
    """One park's content entry, or a ``SystemExit`` listing the parks there are."""
    country = country_of(place_id)
    for entry in park_list(country):
        if entry["id"] == place_id:
            return entry
    known = ", ".join(entry["id"] for entry in park_list(country))
    raise SystemExit(f"unknown park {place_id!r}. Known parks: {known}")


def outlines(country: str, *, online: bool = True) -> dict[str, list[outline.Polygon]]:
    """Every national park's outline in ``country``, by place ID."""
    if country == "jp":
        return _japan(online=online)
    if country == "no":
        return _norway(online=online)
    if country == "nz":
        return _new_zealand(online=online)
    raise ValueError(f"no parks abroad for {country!r}; known: {', '.join(COUNTRIES)}")


def outline_of(place_id: str, *, online: bool = True) -> list[outline.Polygon]:
    found = outlines(country_of(place_id), online=online).get(place_id)
    if not found:
        raise SystemExit(f"no outline for {place_id} in the raw store or at its source")
    return found


# MARK: - Japan


def _japan(*, online: bool) -> dict[str, list[outline.Polygon]]:
    from ..jp import geometry, shapefile

    path = _source_file("jp")
    if path is None:
        if not online:
            raise SystemExit("no nps.zip in the raw store; fetch online first")
        path = _download_nps_zip()
    by_name = {
        str(entry["localName"]).removesuffix("国立公園"): entry["id"] for entry in park_list("jp")
    }
    zones: dict[str, list[outline.Polygon]] = {}
    for feature in shapefile.read_zip(path):
        park_id = by_name.get(str(feature.attributes.get("NAME") or "").strip())
        if park_id:
            zones.setdefault(park_id, []).extend(feature.polygons)
    return {park_id: geometry.union(polygons) for park_id, polygons in zones.items()}


def _download_nps_zip() -> Path:
    directory = rawstore.version_directory(SOURCES["jp"])
    record = FetchRecord(source=TERMS["jp"], fetched_at=rawstore.utc_now())
    with http.client(http.Politeness(timeout_seconds=600.0)) as session:
        response = http.get(session, NPS_ZIP_URL, expect="application")
        path = http.write_bytes(directory / NPS_ZIP, response.content)
        record.add_request(
            NPS_ZIP_URL,
            last_modified=response.headers.get("last-modified"),
        )
    record.add_file(path, root=directory)
    record.write(directory)
    return path


# MARK: - Norway


def _norway(*, online: bool) -> dict[str, list[outline.Polygon]]:
    path = _source_file("no")
    if path is None:
        if not online:
            raise SystemExit("no Naturvernområder national parks in the raw store")
        path = _download_naturvern()
    by_naturvern = {entry["naturvernId"]: entry["id"] for entry in park_list("no")}
    found: dict[str, list[outline.Polygon]] = {}
    for feature in json.loads(path.read_text()).get("features") or []:
        properties = feature.get("properties") or {}
        park_id = by_naturvern.get(properties.get("naturvernId") or "")
        if park_id:
            found.setdefault(park_id, []).extend(outline.polygons_of(feature.get("geometry")))
    return found


def _download_naturvern() -> Path:
    directory = rawstore.version_directory(SOURCES["no"])
    record = FetchRecord(source=TERMS["no"], fetched_at=rawstore.utc_now())
    features: list[dict[str, Any]] = []
    offset = 0
    with http.client() as session:
        while True:
            parameters = {
                "where": NATIONAL_PARKS_WHERE,
                "outFields": "naturvernId,navn,verneform",
                "returnGeometry": "true",
                "outSR": "4326",
                "geometryPrecision": "6",
                "orderByFields": "OBJECTID",
                "f": "geojson",
                "resultOffset": str(offset),
                "resultRecordCount": "25",
            }
            response = http.get(session, f"{VERN_LAYER}/query", params=parameters,
                                expect="application")
            payload = response.json()
            if "error" in payload:
                raise http.FetchError(f"{VERN_LAYER} refused the query: {payload['error']}")
            record.add_request(f"{VERN_LAYER}/query", parameters)
            page = payload.get("features") or []
            features.extend(page)
            exceeded = payload.get("exceededTransferLimit") or (
                payload.get("properties") or {}
            ).get("exceededTransferLimit")
            if not page or not exceeded:
                break
            offset += len(page)
    path = directory / "national-parks.geojson"
    path.write_text(json.dumps({"type": "FeatureCollection", "features": features}))
    record.add_file(path, root=directory)
    record.write(directory)
    return path


# MARK: - New Zealand


def _new_zealand(*, online: bool) -> dict[str, list[outline.Polygon]]:
    path = _source_file("nz")
    if path is None:
        if not online:
            raise SystemExit("no Public Conservation Land national parks in the raw store")
        path = _download_pcl()
    by_napalis = {str(entry["napalisId"]): entry["id"] for entry in park_list("nz")}
    found: dict[str, list[outline.Polygon]] = {}
    for feature in json.loads(path.read_text()).get("features") or []:
        properties = feature.get("properties") or {}
        park_id = by_napalis.get(str(properties.get("NaPALIS_ID") or ""))
        if park_id:
            found.setdefault(park_id, []).extend(outline.polygons_of(feature.get("geometry")))
    return found


def _download_pcl() -> Path:
    directory = rawstore.version_directory(SOURCES["nz"])
    record = FetchRecord(source=TERMS["nz"], fetched_at=rawstore.utc_now())
    features: list[dict[str, Any]] = []
    offset = 0
    with http.client() as session:
        while True:
            parameters = {
                "where": PCL_NATIONAL_PARKS_WHERE,
                "outFields": "NaPALIS_ID,Name,Section",
                "returnGeometry": "true",
                "outSR": "4326",
                "geometryPrecision": "6",
                "orderByFields": "OBJECTID",
                "f": "geojson",
                "resultOffset": str(offset),
                "resultRecordCount": "2",
            }
            response = http.get(session, f"{PCL_LAYER}/query", params=parameters,
                                expect="application")
            payload = response.json()
            if "error" in payload:
                raise http.FetchError(f"{PCL_LAYER} refused the query: {payload['error']}")
            record.add_request(f"{PCL_LAYER}/query", parameters)
            page = payload.get("features") or []
            features.extend(page)
            exceeded = payload.get("exceededTransferLimit") or (
                payload.get("properties") or {}
            ).get("exceededTransferLimit")
            if not page or not exceeded:
                break
            offset += len(page)
    path = directory / "national-parks.geojson"
    path.write_text(json.dumps({"type": "FeatureCollection", "features": features}))
    record.add_file(path, root=directory)
    record.write(directory)
    return path


# MARK: - Raw store


def _source_file(country: str) -> Path | None:
    """The newest outline source on disk: the country's own fetch first, then ours."""
    source, filename = COUNTRY_SOURCES[country]
    for name in (source, SOURCES[country]):
        directory = rawstore.latest(name, filename)
        if directory is not None:
            return directory / filename
    return None


def source_directory(country: str) -> Path | None:
    """The raw directory the outlines were read from, for a pack's list of sources."""
    path = _source_file(country)
    return path.parent if path else None


def write_feature(place_id: str, polygons: list[outline.Polygon]) -> Path:
    """One park's outline as GeoJSON in ``raw/<today>/abroad-outlines-<cc>/``, the file a
    pack is built from, with the source's terms beside it."""
    country = country_of(place_id)
    directory = rawstore.version_directory(SOURCES[country])
    path = directory / f"{place_id}.geojson"
    feature = {
        "type": "Feature",
        "properties": {"placeID": place_id},
        "geometry": {
            "type": "MultiPolygon",
            "coordinates": [
                [[[lon, lat] for lon, lat in [*ring, ring[0]]] for ring in polygon]
                for polygon in polygons
            ],
        },
    }
    path.write_text(json.dumps({"type": "FeatureCollection", "features": [feature]}))
    existing = directory / "source.json"
    record = FetchRecord(source=TERMS[country], fetched_at=rawstore.utc_now())
    if existing.exists():
        payload = json.loads(existing.read_text())
        record.requests = list(payload.get("requests") or [])
        record.files = [
            entry for entry in payload.get("files") or [] if entry["path"] != path.name
        ]
    record.add_file(path, root=directory, note=f"{place_id}: outline as read from its source")
    record.write(directory)
    return path
