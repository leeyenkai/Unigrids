"""Fetching for the map's other public lands and its transport layers.

The NPS's own units come from ``reference_fetch``. This module pulls everything else the
atlas draws — every national forest and grassland, every national wildlife refuge, the
BLM's national monuments and conservation areas, every public National Natural Landmark,
every nationally designated scenic byway — and the two transport layers the map can lay
over them: the Interstate and US highway network, and Amtrak.

All of it is federal data published without copyright restriction, from each agency's own
ArcGIS service, and lands in the date-versioned raw store like every other source:

``federal-lands/``
    ``forests``, ``grasslands``, ``refuges``, ``blm-nlcs``, ``landmarks``, ``byways`` and
    ``states`` (state outlines, so places whose source carries no state can be given one).
``transport/``
    ``interstates``, ``us-highways``, ``amtrak-routes`` and ``amtrak-stations``.

Polygons are generalised by the server to about 100 m, which is finer than the build keeps.
Lines are not: the highway service answers a generalisation request forty times slower
than a plain one, so lines arrive at full detail and the build generalises them.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from . import rawstore
from .rawstore import FetchRecord, SourceTerms
from .sources import arcgis, http

USFS_FORESTS = (
    "https://apps.fs.usda.gov/arcx/rest/services/EDW/"
    "EDW_ProclaimedForestsAndGrasslands_01/MapServer/4"
)
USFS_GRASSLANDS = (
    "https://apps.fs.usda.gov/arcx/rest/services/EDW/"
    "EDW_ProclaimedForestsAndGrasslands_01/MapServer/1"
)
FWS_REFUGES = (
    "https://services.arcgis.com/QVENGdaPbd4LUkLV/arcgis/rest/services/"
    "National_Wildlife_Refuge_System_Boundaries/FeatureServer/0"
)
BLM_NLCS = (
    "https://gis.blm.gov/arcgis/rest/services/lands/BLM_Natl_NLCS_NM_NCA_poly/MapServer/1"
)
NPS_LANDMARKS = (
    "https://services1.arcgis.com/fBc8EJBxQRMcHlei/arcgis/rest/services/"
    "NonSensitiveNNLs/FeatureServer/0"
)
FHWA_BYWAYS = (
    "https://services.arcgis.com/xOi1kZaI0eWDREZv/arcgis/rest/services/"
    "FHWA_ScenicByways_08042026_gdb/FeatureServer/0"
)
CENSUS_STATES = (
    "https://tigerweb.geo.census.gov/arcgis/rest/services/TIGERweb/State_County/MapServer/0"
)
NTAD_HIGHWAYS = (
    "https://services.arcgis.com/xOi1kZaI0eWDREZv/arcgis/rest/services/"
    "NTAD_National_Highway_System/FeatureServer/0"
)
NTAD_AMTRAK_ROUTES = (
    "https://services.arcgis.com/xOi1kZaI0eWDREZv/arcgis/rest/services/"
    "NTAD_Amtrak_Routes/FeatureServer/0"
)
NTAD_AMTRAK_STATIONS = (
    "https://services.arcgis.com/xOi1kZaI0eWDREZv/arcgis/rest/services/"
    "NTAD_Amtrak_Stations/FeatureServer/0"
)

LANDS_TERMS = SourceTerms(
    identifier="federal-lands",
    title=(
        "Federal lands: USFS proclaimed forests and grasslands, USFWS refuge boundaries, "
        "BLM National Conservation Lands, NPS National Natural Landmarks, FHWA scenic "
        "byways, Census state outlines"
    ),
    url=FWS_REFUGES,
    licence="US government works, public domain",
    attribution=(
        "Boundaries: US Forest Service, US Fish and Wildlife Service, Bureau of Land "
        "Management; National Natural Landmarks: National Park Service; byways: Federal "
        "Highway Administration; states: US Census Bureau"
    ),
    notes="Each layer is fetched whole; the build decides what the map carries.",
)

TRANSPORT_TERMS = SourceTerms(
    identifier="transport",
    title="National Transportation Atlas Database: National Highway System and Amtrak",
    url=NTAD_HIGHWAYS,
    licence="US government work (17 U.S.C. § 101), unrestricted public use",
    attribution="Highways and Amtrak: US DOT Bureau of Transportation Statistics, NTAD",
    notes="Interstates and US routes from the NHS; Amtrak routes and train stations.",
)

LANDS_FILES = (
    "forests.geojson",
    "grasslands.geojson",
    "refuges.geojson",
    "blm-nlcs.geojson",
    "landmarks.geojson",
    "byways.geojson",
    "states.geojson",
)
TRANSPORT_FILES = (
    "interstates.geojson",
    "us-highways.geojson",
    "amtrak-routes.geojson",
    "amtrak-stations.geojson",
)

# (file, layer, where, fields, server generalisation in degrees or None)
_LANDS_QUERIES: tuple[tuple[str, str, str, str, float | None], ...] = (
    ("forests.geojson", USFS_FORESTS, "1=1", "forest_grasslandname,gis_acres", 0.001),
    ("grasslands.geojson", USFS_GRASSLANDS, "1=1", "grasslandname,gis_acres", 0.001),
    (
        "refuges.geojson",
        FWS_REFUGES,
        "RSL_TYPE='NWR'",
        "ORGNAME,ORGCODE,LIT,FWSREGION",
        0.001,
    ),
    (
        "blm-nlcs.geojson",
        BLM_NLCS,
        "1=1",
        "sma_code,STATE_ADMN,Label,NCA_NAME,NLCS_ID",
        0.001,
    ),
    (
        "landmarks.geojson",
        NPS_LANDMARKS,
        "1=1",
        "NNL_Name,NNL_Code,State,County,Acre_Calc,Unit_Type",
        None,
    ),
    (
        "byways.geojson",
        FHWA_BYWAYS,
        "1=1",
        "BywayID,NAME,STATE,Current_Desig,NSB_Year,AAR_Year",
        None,
    ),
    ("states.geojson", CENSUS_STATES, "1=1", "STUSAB,NAME", 0.01),
)

_TRANSPORT_QUERIES: tuple[tuple[str, str, str, str], ...] = (
    ("interstates.geojson", NTAD_HIGHWAYS, "SIGNT1='I'", "SIGNN1,STFIPS"),
    ("us-highways.geojson", NTAD_HIGHWAYS, "SIGNT1='U'", "SIGNN1,STFIPS"),
    ("amtrak-routes.geojson", NTAD_AMTRAK_ROUTES, "1=1", "name"),
    (
        "amtrak-stations.geojson",
        NTAD_AMTRAK_STATIONS,
        "StnType='TRAIN'",
        "Code,StationName,City,State,StaType",
    ),
)


def fetch_lands(version: str) -> Path:
    directory = rawstore.version_directory("federal-lands", version)
    record = FetchRecord(source=LANDS_TERMS, fetched_at=rawstore.utc_now())
    with http.client() as session:
        for name, layer, where, fields, offset in _LANDS_QUERIES:
            features = arcgis.query_features(
                session,
                layer,
                where=where,
                out_fields=fields,
                record=record,
                max_allowable_offset=offset,
                page_size=200 if offset is not None else 1000,
            )
            _write(directory / name, features, record)
            print(f"    federal-lands/{name}: {len(features)} features", flush=True)
    record.write(directory)
    return directory


def fetch_transport(version: str, *, refresh: bool = False) -> Path:
    directory = rawstore.version_directory("transport", version)
    record = FetchRecord(source=TRANSPORT_TERMS, fetched_at=rawstore.utc_now())
    with http.client() as session:
        for name, layer, where, fields in _TRANSPORT_QUERIES:
            # The US-route layer is two hundred pages; an interrupted fetch resumes at the
            # first file it does not have rather than starting over.
            if (directory / name).exists() and not refresh:
                record.add_file(directory / name, root=directory)
                continue
            features = arcgis.query_features(
                session,
                layer,
                where=where,
                out_fields=fields,
                record=record,
                page_size=2000,
                geometry_precision=4,
            )
            _write(directory / name, features, record)
            print(f"    transport/{name}: {len(features)} features", flush=True)
    record.write(directory)
    return directory


def _write(path: Path, features: list[dict[str, Any]], record: FetchRecord) -> None:
    path.write_text(json.dumps({"type": "FeatureCollection", "features": features}))
    record.add_file(path, root=path.parent)
