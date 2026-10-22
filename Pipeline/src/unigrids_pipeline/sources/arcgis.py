"""ArcGIS REST feature queries, for the two NPS datasets a pack needs.

Both are public and keyless:

* **NPS Public Trails** — ``SPECIFICATION.md`` §8's trail source, a national layer of
  official visitor-use trails maintained by park GIS staff.
* **NPS boundaries** (Land Resources Division) — the park extent a pack is rendered for.
  §12 names PAD-US for boundaries, which is the right source for state parks and other
  agencies' land; for an NPS unit the NPS's own boundary is the authority, and it does not
  need the multi-gigabyte PAD-US download.

ArcGIS caps a response at the layer's ``maxRecordCount`` and says so in
``exceededTransferLimit``, so every query pages until the server stops holding back.
"""

from __future__ import annotations

import time
from typing import Any

import httpx

from . import http

TRAILS_LAYER = (
    "https://mapservices.nps.gov/arcgis/rest/services/NationalDatasets/"
    "NPS_Public_Trails/MapServer/0"
)
BOUNDARY_LAYER = (
    "https://services1.arcgis.com/fBc8EJBxQRMcHlei/arcgis/rest/services/"
    "NPS_Land_Resources_Division_Boundary_and_Tract_Data_Service/FeatureServer/2"
)

TRAIL_FIELDS = (
    "OBJECTID,TRLNAME,TRLALTNAME,MAPLABEL,TRLSTATUS,TRLSURFACE,TRLTYPE,TRLCLASS,TRLUSE,"
    "TRLFEATTYPE,SEASONAL,SEASDESC,OPENTOPUBLIC,PUBLICDISPLAY,UNITCODE,UNITNAME,"
    "GEOMETRYID,MAPSOURCE,SOURCEDATE,XYACCURACY,NOTES"
)
BOUNDARY_FIELDS = "UNIT_CODE,UNIT_NAME,UNIT_TYPE,PARKNAME,STATE,REGION,DATE_EDIT"

PAGE_SIZE = 1000


def query_features(
    session: httpx.Client,
    layer_url: str,
    *,
    where: str,
    out_fields: str,
    page_size: int = PAGE_SIZE,
    record: Any = None,
    max_allowable_offset: float | None = None,
    geometry_precision: int = 6,
) -> list[dict[str, Any]]:
    """Every feature matching ``where``, as GeoJSON features in WGS84.

    ``record`` is an optional :class:`~unigrids_pipeline.rawstore.FetchRecord` to note the
    requests in, so the raw store remembers exactly what was asked for.

    ``max_allowable_offset`` asks the server to generalise the geometry, in degrees. Used
    for the national boundary sweep, where the question is how many tiles a park's outline
    covers and a 100-metre simplification of a 50-kilometre coastline changes nothing but
    the download size.

    ``geometry_precision`` is decimal places in the answer: six (about 10 cm) by default,
    four (about 10 m) for national line layers that are generalised far past that anyway.
    """
    features: list[dict[str, Any]] = []
    offset = 0
    while True:
        parameters = {
            "where": where,
            "outFields": out_fields,
            "returnGeometry": "true",
            "outSR": "4326",
            "geometryPrecision": str(geometry_precision),
            "resultOffset": str(offset),
            "resultRecordCount": str(page_size),
            "f": "geojson",
        }
        if max_allowable_offset is not None:
            parameters["maxAllowableOffset"] = str(max_allowable_offset)
        payload = _query_page(session, layer_url, parameters)
        if record is not None:
            record.add_request(f"{layer_url}/query", parameters)
        page = payload.get("features") or []
        features.extend(page)
        exceeded = payload.get("exceededTransferLimit") or (
            payload.get("properties") or {}
        ).get("exceededTransferLimit")
        if not page or not exceeded:
            return features
        offset += len(page)


def _query_page(
    session: httpx.Client, layer_url: str, parameters: dict[str, str]
) -> dict[str, Any]:
    """One page of a query. A hosted layer under load sometimes answers a valid page with
    a bare 400, and the same request a moment later succeeds, so a refusal is retried
    twice before it is believed."""
    for attempt in range(3):
        response = http.get(session, f"{layer_url}/query", params=parameters, expect="application")
        payload = response.json()
        if "error" not in payload:
            return payload
        if attempt < 2:
            time.sleep(5 * (attempt + 1))
    raise http.FetchError(f"{layer_url} refused the query: {payload['error']}")


def trails_for_unit(
    session: httpx.Client, unit_code: str, *, record: Any = None
) -> list[dict[str, Any]]:
    return query_features(
        session,
        TRAILS_LAYER,
        where=f"UNITCODE='{unit_code}'",
        out_fields=TRAIL_FIELDS,
        record=record,
    )


def boundary_for_unit(
    session: httpx.Client, unit_code: str, *, record: Any = None
) -> list[dict[str, Any]]:
    return query_features(
        session,
        BOUNDARY_LAYER,
        where=f"UNIT_CODE='{unit_code}'",
        out_fields=BOUNDARY_FIELDS,
        record=record,
    )


def national_park_boundaries(
    session: httpx.Client, *, record: Any = None, max_allowable_offset: float | None = 0.001
) -> list[dict[str, Any]]:
    """Every one of the 63 national parks' boundaries — how the extrapolation gets real.

    Asking the boundary service for all 63 outlines is what turns "how big would the other
    62 packs be" from a guess into a calculation: each park's real shape, buffered and
    counted exactly as Zion's was.

    Two wrinkles in the service's own classification, and both are handled rather than
    rounded off:

    * **New River Gorge** is typed ``National Preserves`` here, not ``National Parks``,
      although it has been a national park since 2020. Without it the sweep returns 62.
    * A **park and preserve** — Denali, Wrangell–St. Elias, Gates of the Arctic and the
      rest — is two rows with one park code. Both are kept, because a pack for Denali
      that stopped at the park half would be the wrong size.
    """
    codes = {
        (feature.get("properties") or {}).get("UNIT_CODE")
        for feature in query_features(
            session,
            BOUNDARY_LAYER,
            where="UNIT_TYPE='National Parks' OR UNIT_CODE='NERI'",
            out_fields="UNIT_CODE",
            record=record,
            max_allowable_offset=0.05,
        )
    }
    codes.discard(None)
    quoted = ",".join(f"'{code}'" for code in sorted(codes))
    return query_features(
        session,
        BOUNDARY_LAYER,
        where=f"UNIT_CODE IN ({quoted})",
        out_fields=BOUNDARY_FIELDS,
        record=record,
        max_allowable_offset=max_allowable_offset,
    )


def feature_collection(features: list[dict[str, Any]], **properties: Any) -> dict[str, Any]:
    return {"type": "FeatureCollection", **properties, "features": features}
