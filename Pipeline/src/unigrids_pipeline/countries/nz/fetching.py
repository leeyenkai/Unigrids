"""Fetching New Zealand's sources into the date-versioned raw store.

Every source lands in ``raw/<date>/nz-<source>/`` with a ``source.json`` beside it, and
every step resumes where an earlier run stopped: a file already in today's snapshot is left
alone unless ``refresh`` asks otherwise.

``nz-pcl/``
    DOC's Public Conservation Land: the 13 national parks (``S4_NATIONAL_PARK``) and every
    conservation and forest park (``S19_CONSERVATION_PARK``), with their geometry in WGS84
    (CC BY 4.0).
``nz-regions/``
    Stats NZ's regional councils, as Eagle Technology hosts them (CC BY 4.0).
``nz-doc-facilities/``
    DOC's huts, campsites and visitor centres: the asset layers (``*_Open_Data``) and the
    website layers beside them that carry each hut's and campsite's page and booking.
``nz-doc-tracks/``
    DOC Tracks, the whole layer.
``nz-wikidata/``, ``nz-wikipedia/``, ``nz-commons/``, ``nz-photos/``
    New Zealand's protected areas on Wikidata, English Wikipedia leads for the conservation
    parks, Commons licence metadata for every photograph a guide or item names, and the
    guides' photographs themselves.
``nz-documents/``
    Each national park's page on doc.govt.nz and the PDFs it links, each checked with a
    HEAD request.
``nz-osm/``
    Passenger rail routes and stations, read out of Geofabrik's New Zealand extract
    (ODbL); the extract is fetched only while a file read from it is missing.
``nz-climate/``
    Ten years of Open-Meteo daily weather at each park's centre (``climate``).

Requests identify the app and nothing else, and pause between calls.
"""

from __future__ import annotations

import html as html_lib
import json
import re
import time
from pathlib import Path
from typing import Any
from urllib.parse import urljoin

import httpx

from ... import __version__, climate, geo, outline, rawstore
from ...rawstore import FetchRecord, SourceTerms
from ...sources import http, osm_pbf
from ..common import photo_filename
from ..no import fetching as shared
from . import content, rules, tracks, wiki

USER_AGENT = shared.USER_AGENT

# Raw store sources.
PCL = "nz-pcl"
REGIONS = "nz-regions"
FACILITIES = "nz-doc-facilities"
TRACKS = tracks.SOURCE
WIKIDATA = "nz-wikidata"
WIKIPEDIA = "nz-wikipedia"
COMMONS = "nz-commons"
PHOTOS = "nz-photos"
DOCUMENTS = "nz-documents"
OSM = "nz-osm"
CLIMATE = "nz-climate"

# MARK: - Endpoints and terms

DOC_SERVICES = "https://services1.arcgis.com/3JjYDyG3oajxU6HO/ArcGIS/rest/services"
PCL_LAYER = f"{DOC_SERVICES}/DOC_Public_Conservation_Land_FHV/FeatureServer/0"
TRACKS_LAYER = f"{DOC_SERVICES}/DOC_Tracks_Open_Data/FeatureServer/0"
HUTS_LAYER = f"{DOC_SERVICES}/DOC_Huts_Open_Data/FeatureServer/0"
HUTS_WEB_LAYER = f"{DOC_SERVICES}/DOC_Huts/FeatureServer/0"
CAMPSITES_LAYER = f"{DOC_SERVICES}/DOC_Campsites_Open_Data/FeatureServer/0"
CAMPSITES_WEB_LAYER = f"{DOC_SERVICES}/DOC_Campsites/FeatureServer/0"
VISITOR_CENTRES_LAYER = f"{DOC_SERVICES}/DOC_Vistor_Centres_DTO/FeatureServer/0"
REGIONS_LAYER = (
    "https://services.arcgis.com/XTtANUDT8Va4DLwI/arcgis/rest/services/"
    "nz_regional_councils/FeatureServer/0"
)

PCL_FIELDS = (
    "NaPALIS_ID,Name,Section,Legislation,Type,Start_Date,Recorded_Area,Control_Managed,"
    "Shape__Area"
)
PCL_QUERIES = {
    "national-parks.geojson": f"Section = '{rules.NATIONAL_PARK_SECTION}'",
    "conservation-parks.geojson": f"Section = '{rules.CONSERVATION_PARK_SECTION}'",
}
# What the counts file records: every tier, and whether Te Urewera, a legal person of its
# own since 2014 and no longer DOC's, is in the layer at all.
PCL_COUNTS = {
    "nationalParks": f"Section = '{rules.NATIONAL_PARK_SECTION}'",
    "conservationParks": f"Section = '{rules.CONSERVATION_PARK_SECTION}'",
    "teUrewera": "Name LIKE '%Urewera%'",
}
EXPECTED_NATIONAL_PARKS = 13

FACILITY_QUERIES = {
    "huts.geojson": (HUTS_LAYER, "*"),
    "huts-web.geojson": (HUTS_WEB_LAYER, "name,assetId,staticLink,bookable,place,region"),
    "campsites.geojson": (CAMPSITES_LAYER, "*"),
    "campsites-web.geojson": (
        CAMPSITES_WEB_LAYER, "name,assetId,staticLink,bookable,place,region,campsiteCategory",
    ),
    "visitor-centres.geojson": (VISITOR_CENTRES_LAYER, "*"),
}

DOC_ATTRIBUTION = "Crown Copyright: Department of Conservation Te Papa Atawhai"

PCL_TERMS = SourceTerms(
    identifier="nz-pcl",
    title="DOC Public Conservation Land (NaPALIS protected areas): national parks and "
    "conservation parks",
    url=PCL_LAYER,
    licence="CC BY 4.0",
    attribution=DOC_ATTRIBUTION,
    notes="Geometry in WGS84 (outSR 4326). Outlines are simplified by Unigrids before they "
    "ship. Te Urewera is not in the layer: since the Te Urewera Act 2014 it is not "
    "conservation land.",
)
REGION_TERMS = SourceTerms(
    identifier="nz-regions",
    title="Stats NZ regional councils (clipped), as hosted by Eagle Technology",
    url=REGIONS_LAYER,
    licence="CC BY 4.0",
    attribution="Contains data sourced from Stats NZ licensed for reuse under CC BY 4.0",
    notes="Generalised by the service to about 100 m (maxAllowableOffset 0.001°); used only "
    "to say which regions a place lies in.",
)
FACILITY_TERMS = SourceTerms(
    identifier="nz-doc-facilities",
    title="DOC Huts, DOC Campsites (asset and website layers) and DOC visitor centres",
    url=DOC_SERVICES,
    licence="CC BY 4.0",
    attribution=DOC_ATTRIBUTION,
    notes="The asset layers decide what is open and in public use; the website layers, "
    "joined on the asset number, give each place's page on doc.govt.nz and its booking.",
)
TRACK_TERMS = SourceTerms(
    identifier="nz-doc-tracks",
    title="DOC Tracks (DOC_Tracks_Open_Data)",
    url=TRACKS_LAYER,
    licence="CC BY 4.0",
    attribution=DOC_ATTRIBUTION,
    notes="Every track record, in WGS84. Most geometry is DOC's own 'automatically "
    "generated' line; the build keeps open, public walking tracks.",
)
WIKIDATA_TERMS = SourceTerms(
    identifier="nz-wikidata",
    title="Wikidata: New Zealand's protected areas and parks",
    url=shared.SPARQL,
    licence="CC0",
    attribution="Wikidata",
    notes="Used for each place's English Wikipedia article, P18 image and Commons category.",
)
WIKIPEDIA_TERMS = SourceTerms(
    identifier="nz-wikipedia",
    title="English Wikipedia leads (Action API, intro extracts) for New Zealand's "
    "conservation parks",
    url=shared.WIKIPEDIA_API,
    licence="CC BY-SA 4.0",
    attribution="Summaries: Wikipedia, CC BY-SA 4.0, linked from each place",
)
COMMONS_TERMS = SourceTerms(
    identifier="nz-commons",
    title="Wikimedia Commons licence and author metadata",
    url=shared.COMMONS_API,
    licence="Per file",
    attribution="Photographs credited individually, via Wikimedia Commons",
    notes="Every photograph keeps its credit and licence, and is marked public domain only "
    "when its licence says so.",
)
PHOTO_TERMS = SourceTerms(
    identifier="nz-photos",
    title="Wikimedia Commons photographs named in New Zealand's guides",
    url=shared.COMMONS_FILE_PATH,
    licence="Per file (see nz-commons/licences.json)",
    attribution="Photographs credited individually, via Wikimedia Commons",
    notes=f"Downloaded at {shared.PHOTO_WIDTH} px wide and resized by the build.",
)
DOCUMENT_TERMS = SourceTerms(
    identifier="nz-documents",
    title="DOC national park pages on doc.govt.nz and the PDFs they link",
    url="https://www.doc.govt.nz/parks-and-recreation/places-to-go/national-parks/",
    licence="Crown copyright; links only, nothing is extracted",
    attribution=DOC_ATTRIBUTION,
    notes="Each page read as HTML; every PDF checked with HEAD.",
)
OSM_TERMS = SourceTerms(
    identifier="openstreetmap-nz",
    title="OpenStreetMap from the Geofabrik extract: passenger rail and stations",
    url="https://www.openstreetmap.org/copyright",
    licence="Open Database License (ODbL) 1.0",
    attribution="© OpenStreetMap contributors",
    notes="route=train relations touching New Zealand with their member ways and stops, "
    "and railway stations, read out of Geofabrik's new-zealand .osm.pbf and written in "
    "Overpass's `out geom` shape. Shipped as data: a Derivative Database under the ODbL.",
)

# South, west, north, east: the North and South Islands and Rakiura. The Chathams have no
# railway.
RAIL_BOX = (-47.4, 166.3, -34.3, 178.7)
RAIL_FILE = "rail-routes-nz.json"
STATIONS_FILE = "stations.json"


def client() -> httpx.Client:
    return shared.client()


def _skip(path: Path, refresh: bool) -> bool:
    return path.exists() and not refresh


def _write_record(record: FetchRecord, directory: Path) -> None:
    shared._write_record(record, directory)


# MARK: - Fetch


def fetch(*, refresh: bool = False) -> Path:
    """Fetch everything New Zealand's ``assemble`` reads into ``raw/<today>/``. Returns the
    version directory."""
    version = rawstore.today()
    root = rawstore.version_directory(PCL, version).parent
    with client() as session:
        _fetch_pcl(session, version, refresh=refresh)
        _fetch_regions(session, version, refresh=refresh)
        _fetch_facilities(session, version, refresh=refresh)
        _fetch_tracks(session, version, refresh=refresh)
        areas = read_areas(root / PCL)
        _fetch_wikidata(session, version, refresh=refresh)
        matches = second_tier_matches(root / WIKIDATA, areas)
        _fetch_wikipedia(session, version, matches, refresh=refresh)
        _fetch_commons(session, version, matches, refresh=refresh)
        _fetch_photos(session, version, refresh=refresh)
        _fetch_documents(session, version, refresh=refresh)
        _fetch_climate(session, version, areas, refresh=refresh)
    outlines = {
        park["id"]: area.polygons for park, area in national_parks(areas) if area is not None
    }
    _fetch_osm(version, outlines, refresh=refresh)
    # Trails: DOC Tracks for every park, OpenStreetMap for any it leaves without one; then
    # the elevation tiles the kept routes cross.
    from ..abroad import trails as abroad_trails

    abroad_trails.fetch("nz", list(content.parks()), outlines, refresh=False)
    return root


def arcgis_query(
    session: httpx.Client,
    layer: str,
    parameters: dict[str, str],
    *,
    record: FetchRecord | None = None,
    page_size: int = 100,
) -> list[dict[str, Any]]:
    return shared.arcgis_query(session, layer, parameters, record=record, page_size=page_size)


def _collection(features: list[dict[str, Any]]) -> str:
    return json.dumps({"type": "FeatureCollection", "features": features}, ensure_ascii=False)


# MARK: - Public Conservation Land


def _fetch_pcl(session: httpx.Client, version: str, *, refresh: bool) -> None:
    directory = rawstore.version_directory(PCL, version)
    record = FetchRecord(source=PCL_TERMS, fetched_at=rawstore.utc_now())
    for name, where in PCL_QUERIES.items():
        path = directory / name
        if _skip(path, refresh):
            print(f"    {PCL}/{name}: already fetched today")
            continue
        features = arcgis_query(
            session, PCL_LAYER,
            {"where": where, "outFields": PCL_FIELDS, "orderByFields": "OBJECTID"},
            record=record,
            # Fiordland alone is tens of thousands of vertices; parks come two at a time.
            page_size=2 if name == "national-parks.geojson" else 20,
        )
        path.write_text(_collection(features))
        record.add_file(path, root=directory)
        print(f"    {PCL}/{name}: {len(features)} features")
    counts_path = directory / "counts.json"
    if not _skip(counts_path, refresh):
        counts = {}
        for key, where in PCL_COUNTS.items():
            response = http.get(
                session, f"{PCL_LAYER}/query",
                params={"where": where, "returnCountOnly": "true", "f": "json"},
                expect="application",
            )
            counts[key] = response.json().get("count")
            record.add_request(f"{PCL_LAYER}/query", {"where": where, "returnCountOnly": True})
        counts_path.write_text(json.dumps(counts, indent=1) + "\n")
        record.add_file(counts_path, root=directory)
        print(f"    {PCL}: in the whole layer {counts}")
    _write_record(record, directory)


class Area:
    """One Public Conservation Land record as fetched: its properties and outline."""

    def __init__(self, feature: dict[str, Any], tier: str) -> None:
        self.properties: dict[str, Any] = feature.get("properties") or {}
        self.tier = tier
        self.polygons: list[outline.Polygon] = outline.polygons_of(feature.get("geometry"))
        self.parts: list[dict[str, Any]] = [self.properties]

    @property
    def napalis_id(self) -> str:
        value = self.properties.get("NaPALIS_ID")
        return str(int(value)) if isinstance(value, int | float) else str(value or "")

    @property
    def name(self) -> str:
        return re.sub(r"\s+", " ", self.properties.get("Name") or "").strip()

    @property
    def area_m2(self) -> float:
        return sum(rules.gis_area_m2(part) for part in self.parts)

    @property
    def recorded_hectares(self) -> float | None:
        """DOC's recorded area, summed over a park's parcels where every one records it."""
        values = [rules.recorded_hectares(part) for part in self.parts]
        if not values or any(value is None for value in values):
            return None
        return round(sum(value for value in values if value is not None), 1)

    def merge(self, other: Area) -> None:
        """Another record of the same park (a parcel): one more piece of its outline."""
        self.polygons.extend(other.polygons)
        self.parts.extend(other.parts)

    @property
    def centre(self) -> tuple[float, float] | None:
        return outline.label_point(self.polygons)

    @property
    def box(self) -> geo.BoundingBox | None:
        found = outline.bbox(self.polygons)
        if found is None:
            return None
        south, west, north, east = found
        return geo.BoundingBox(west=west, south=south, east=east, north=north)

    @property
    def reach_km(self) -> float:
        """Half the outline's diagonal: how far from the centre an item about it may lie."""
        found = outline.bbox(self.polygons)
        if found is None:
            return 0.0
        south, west, north, east = found
        return wiki.distance_km((south, west), (north, east)) / 2


def read_areas(directory: Path | None) -> dict[str, Area]:
    """``NaPALIS_ID`` → the record, for every national park and conservation park
    fetched. A parcel ("Conservation Park - North West Nelson Forest Park - Clark River")
    is joined to the park it belongs to."""
    areas: dict[str, Area] = {}
    if directory is None:
        return areas
    parcels: list[Area] = []
    for name, tier in (("national-parks.geojson", "np"), ("conservation-parks.geojson", "cp")):
        path = directory / name
        if not path.exists():
            continue
        for feature in json.loads(path.read_text()).get("features") or []:
            area = Area(feature, tier)
            if not area.napalis_id:
                continue
            if area.napalis_id in areas:
                areas[area.napalis_id].merge(area)
            elif tier == "cp" and rules.is_parcel(area.name):
                parcels.append(area)
            else:
                areas[area.napalis_id] = area
    parks = {area.name: area for area in areas.values() if area.tier == "cp"}
    for parcel in parcels:
        parent = rules.parent_of(parcel.name, list(parks))
        if parent is not None:
            parks[parent].merge(parcel)
        else:
            areas[parcel.napalis_id] = parcel
    return areas


def national_parks(areas: dict[str, Area]) -> list[tuple[dict[str, Any], Area | None]]:
    """Each park in the content list with its Public Conservation Land record."""
    return [(park, areas.get(str(park["napalisId"]))) for park in content.parks()]


def second_tier(areas: dict[str, Area]) -> list[Area]:
    """Every conservation and forest park of 5 km² or more, in ``NaPALIS_ID`` order so
    identifiers are minted the same way every run."""
    chosen = [
        area for area in areas.values()
        if area.tier == "cp" and area.area_m2 >= rules.MINIMUM_AREA_M2
    ]
    return sorted(chosen, key=lambda area: int(area.napalis_id))


def left_out(areas: dict[str, Area]) -> list[Area]:
    """The conservation park records under the threshold, for the build's report."""
    return sorted(
        (area for area in areas.values()
         if area.tier == "cp" and area.area_m2 < rules.MINIMUM_AREA_M2),
        key=lambda area: area.name,
    )


# MARK: - Regions


def _fetch_regions(session: httpx.Client, version: str, *, refresh: bool) -> None:
    directory = rawstore.version_directory(REGIONS, version)
    path = directory / "regions.geojson"
    if _skip(path, refresh):
        print(f"    {REGIONS}: already fetched today")
        return
    record = FetchRecord(source=REGION_TERMS, fetched_at=rawstore.utc_now())
    features = arcgis_query(
        session, REGIONS_LAYER,
        {"where": "1=1", "outFields": "REGC_code,REGC_name,dataset_year",
         "maxAllowableOffset": "0.001", "orderByFields": "REGC_code"},
        record=record, page_size=4,
    )
    path.write_text(_collection(features))
    record.add_file(path, root=directory)
    _write_record(record, directory)
    print(f"    {REGIONS}: {len(features)} regions")


def read_regions(path: Path) -> dict[str, list[outline.Polygon]]:
    """ISO code → its polygons. The area outside any region is kept only for its pieces
    east of 180°, the Chatham Islands."""
    regions: dict[str, list[outline.Polygon]] = {}
    for feature in json.loads(path.read_text()).get("features") or []:
        properties = feature.get("properties") or {}
        for polygon in outline.polygons_of(feature.get("geometry")):
            longitude = polygon[0][0][0] if polygon and polygon[0] else None
            code = rules.iso_code(str(properties.get("REGC_code") or ""), longitude)
            if code:
                regions.setdefault(code, []).append(polygon)
    return regions


# MARK: - Huts, campsites, visitor centres and tracks


def _fetch_facilities(session: httpx.Client, version: str, *, refresh: bool) -> None:
    directory = rawstore.version_directory(FACILITIES, version)
    record = FetchRecord(source=FACILITY_TERMS, fetched_at=rawstore.utc_now())
    for name, (layer, fields) in FACILITY_QUERIES.items():
        path = directory / name
        if _skip(path, refresh):
            continue
        features = arcgis_query(
            session, layer,
            {"where": "1=1", "outFields": fields, "orderByFields": "OBJECTID"},
            record=record, page_size=1000,
        )
        path.write_text(_collection(features))
        record.add_file(path, root=directory)
        print(f"    {FACILITIES}/{name}: {len(features)} records")
    _write_record(record, directory)


def _fetch_tracks(session: httpx.Client, version: str, *, refresh: bool) -> None:
    directory = rawstore.version_directory(TRACKS, version)
    path = directory / tracks.FILE
    if _skip(path, refresh):
        print(f"    {TRACKS}: already fetched today")
        return
    record = FetchRecord(source=TRACK_TERMS, fetched_at=rawstore.utc_now())
    features = arcgis_query(
        session, TRACKS_LAYER,
        {"where": "1=1", "outFields": "*", "orderByFields": "OBJECTID"},
        record=record, page_size=500,
    )
    path.write_text(_collection(features))
    record.add_file(path, root=directory)
    _write_record(record, directory)
    print(f"    {TRACKS}: {len(features)} records")


def read_layer(directory: Path | None, name: str) -> list[dict[str, Any]]:
    if directory is None or not (directory / name).exists():
        return []
    return json.loads((directory / name).read_text()).get("features") or []


# MARK: - Wikidata, Wikipedia and Commons


def _fetch_wikidata(session: httpx.Client, version: str, *, refresh: bool) -> None:
    directory = rawstore.version_directory(WIKIDATA, version)
    path = directory / "candidates.json"
    if _skip(path, refresh):
        return
    record = FetchRecord(source=WIKIDATA_TERMS, fetched_at=rawstore.utc_now())
    payload = shared._sparql(session, wiki.CANDIDATE_QUERY, record)
    path.write_text(json.dumps(payload, ensure_ascii=False))
    record.add_file(path, root=directory)
    _write_record(record, directory)
    rows = len((payload.get("results") or {}).get("bindings") or [])
    print(f"    {WIKIDATA}/candidates.json: {rows} rows")


def read_candidates(directory: Path | None) -> list[dict[str, Any]]:
    path = directory / "candidates.json" if directory else None
    if not path or not path.exists():
        return []
    bindings = (json.loads(path.read_text()).get("results") or {}).get("bindings") or []
    return wiki.candidates(bindings)


def match_name(area: Area) -> str:
    """The name a place is looked for under on Wikidata: a national park's with its
    designation, a conservation park's as the app shows it with its designation back on
    where it was taken off ("Kaimanawa Forest Park", "Waipoua Forest")."""
    if area.tier == "cp" and rules.part_of(area.name) is not None:
        return rules.display_name(area.name)[0]
    return area.name


def wiki_matches(
    areas: dict[str, Area], others: list[dict[str, Any]]
) -> dict[str, dict[str, Any]]:
    """``NaPALIS_ID`` → the Wikidata item that is the place's own, the national parks and
    the second tier matched together so a park's item is never a neighbour's."""
    parks = [area for _, area in national_parks(areas) if area is not None]
    return wiki.own_matches(
        (
            (area.napalis_id, area.tier, match_name(area), area.centre, area.reach_km)
            for area in [*parks, *second_tier(areas)]
        ),
        others,
    )


def second_tier_matches(
    wikidata_dir: Path, areas: dict[str, Area]
) -> dict[str, dict[str, Any]]:
    found = wiki_matches(areas, read_candidates(wikidata_dir))
    chosen = second_tier(areas)
    matches = {
        area.napalis_id: found[area.napalis_id] for area in chosen if area.napalis_id in found
    }
    with_article = sum(1 for item in matches.values() if item.get("article"))
    print(
        f"    {WIKIDATA}: {len(matches)} of {len(chosen)} conservation parks matched, "
        f"{with_article} with an English article"
    )
    return matches


def _load(path: Path, refresh: bool) -> dict[str, Any]:
    if refresh or not path.exists():
        return {}
    return json.loads(path.read_text())


def _fetch_wikipedia(
    session: httpx.Client, version: str, matches: dict[str, dict[str, Any]], *, refresh: bool
) -> None:
    """The English lead of each matched article, twenty to a request (Norway's way)."""
    directory = rawstore.version_directory(WIKIPEDIA, version)
    path = directory / "summaries.json"
    summaries = _load(path, refresh)
    record = FetchRecord(source=WIKIPEDIA_TERMS, fetched_at=rawstore.utc_now())
    wanted = [
        (key, title)
        for key, item in sorted(matches.items())
        if (title := wiki.article_title(item.get("article"))) and key not in summaries
    ]
    for batch in shared._chunks(wanted, 20):
        parameters = {
            "action": "query", "format": "json", "formatversion": "2",
            "prop": "extracts|info|pageprops", "exintro": "1", "explaintext": "1",
            "inprop": "url", "ppprop": "disambiguation", "redirects": "1",
            "titles": "|".join(title for _, title in batch),
        }
        payload = shared.wikimedia_get(session, shared.WIKIPEDIA_API, parameters)
        if payload is None:
            print(f"    {WIKIPEDIA}: a batch of {len(batch)} failed; run again to resume")
            continue
        record.add_request(shared.WIKIPEDIA_API, parameters)
        query = payload.get("query") or {}
        pages = {page.get("title"): page for page in query.get("pages") or []}
        for key, title in batch:
            page = pages.get(shared._resolved(query, title))
            if not page or page.get("missing") or not page.get("extract"):
                continue
            summaries[key] = {
                "title": page["title"],
                "pageid": page.get("pageid"),
                "type": "disambiguation"
                if "disambiguation" in (page.get("pageprops") or {})
                else "standard",
                "extract": page["extract"],
                "content_urls": {"desktop": {"page": page.get("fullurl")}},
            }
    path.write_text(json.dumps(summaries, ensure_ascii=False, indent=1))
    record.add_file(path, root=directory)
    _write_record(record, directory)
    print(f"    {WIKIPEDIA}: {len(summaries)} summaries ({len(wanted)} asked for now)")


def _fetch_commons(
    session: httpx.Client, version: str, matches: dict[str, dict[str, Any]], *, refresh: bool
) -> None:
    """Licence and author for every photograph a guide names and every conservation
    park's P18 image, fifty files to a request."""
    directory = rawstore.version_directory(COMMONS, version)
    path = directory / "licences.json"
    licences = _load(path, refresh)
    record = FetchRecord(source=COMMONS_TERMS, fetched_at=rawstore.utc_now())
    wanted: list[str] = []
    for park in content.parks():
        for photo in content.guide_photos(park["id"]):
            if (name := content.commons_name(photo.get("file"))) and name not in wanted:
                wanted.append(name)
    for item in matches.values():
        if (name := wiki.file_name(item.get("image"))) and name not in wanted:
            wanted.append(name)
    pending = [name for name in wanted if not licences.get(name)]
    for batch in shared._chunks(pending, 50):
        parameters = {
            "action": "query", "format": "json", "formatversion": "2",
            "prop": "imageinfo", "iiprop": "extmetadata|url|user", "iiurlwidth": "1280",
            "titles": "|".join(f"File:{name}" for name in batch),
        }
        payload = shared.wikimedia_get(session, shared.COMMONS_API, parameters)
        if payload is None:
            print(f"    {COMMONS}: a batch of {len(batch)} failed; run again to resume")
            continue
        record.add_request(shared.COMMONS_API, {**parameters, "titles": f"{len(batch)} files"})
        query = payload.get("query") or {}
        pages = {page.get("title"): page for page in query.get("pages") or []}
        for name in batch:
            page = pages.get(shared._resolved(query, f"File:{name}")) or {}
            info = (page.get("imageinfo") or [None])[0]
            if not info:
                licences[name] = None
                continue
            meta = info.get("extmetadata") or {}
            licences[name] = {
                "file": name,
                "licence": (meta.get("LicenseShortName") or {}).get("value"),
                "licenceURL": (meta.get("LicenseUrl") or {}).get("value"),
                "artist": (meta.get("Artist") or {}).get("value"),
                "credit": (meta.get("Credit") or {}).get("value"),
                "uploader": info.get("user"),
                "thumbURL": info.get("thumburl"),
                "descriptionURL": info.get("descriptionurl"),
            }
    path.write_text(json.dumps(licences, ensure_ascii=False, indent=1))
    record.add_file(path, root=directory)
    _write_record(record, directory)
    missing = sum(1 for name in wanted if not licences.get(name))
    print(f"    {COMMONS}: {len(wanted)} files, {len(pending)} asked for now, {missing} not found")


def photo_url(name: str) -> str:
    """Where a guide photograph is downloaded from, and so its name in the raw store."""
    return shared.photo_url(name)


def _fetch_photos(session: httpx.Client, version: str, *, refresh: bool) -> None:
    directory = rawstore.version_directory(PHOTOS, version)
    record = FetchRecord(source=PHOTO_TERMS, fetched_at=rawstore.utc_now())
    fetched = failed = 0
    for park in content.parks():
        for photo in content.guide_photos(park["id"]):
            name = content.commons_name(photo.get("file"))
            if not name:
                continue
            url = photo_url(name)
            path = directory / photo_filename(url)
            if _skip(path, refresh):
                continue
            try:
                response = http.get(session, url, expect="image/")
            except http.FetchError as error:
                print(f"    {PHOTOS}: {park['id']} {name!r} failed ({error})")
                failed += 1
                continue
            path.write_bytes(response.content)
            record.add_file(path, root=directory, note=f"{park['id']}: {name}")
            fetched += 1
    _write_record(record, directory)
    print(f"    {PHOTOS}: {fetched} downloaded, {failed} failed")


# MARK: - Documents


_ANCHOR = re.compile(r"""<a\b[^>]*href=["']([^"']+?\.pdf(?:\?[^"']*)?)["'][^>]*>(.*?)</a>""",
                     re.IGNORECASE | re.DOTALL)


def pdf_links(page_url: str, html: str) -> list[dict[str, str]]:
    """Every PDF a DOC page links, absolute, once each, with the link's text as its title
    where the page gives one."""
    found: list[dict[str, str]] = []
    seen: set[str] = set()
    for href, text in _ANCHOR.findall(html):
        url = urljoin(page_url, href.strip().replace("&amp;", "&"))
        if url in seen:
            continue
        seen.add(url)
        label = re.sub(r"\s+", " ", html_lib.unescape(re.sub(r"<[^>]+>", " ", text))).strip()
        # "Fiordland day walks brochure (PDF, 5,867K)": the size is the file's, not its title.
        label = re.sub(r"\s*\(\s*PDF\b[^)]*\)?\s*$", "", label, flags=re.IGNORECASE).strip()
        found.append({"title": label, "url": url})
    return found


def _fetch_documents(session: httpx.Client, version: str, *, refresh: bool) -> None:
    directory = rawstore.version_directory(DOCUMENTS, version)
    pages_dir = directory / "pages"
    pages_dir.mkdir(exist_ok=True)
    record = FetchRecord(source=DOCUMENT_TERMS, fetched_at=rawstore.utc_now())
    heads_path = directory / "heads.json"
    heads: dict[str, Any] = _load(heads_path, refresh)
    links: dict[str, Any] = {}
    for park in content.parks():
        url = park.get("docPage")
        if not url:
            continue
        path = pages_dir / f"{park['id']}.html"
        if _skip(path, refresh):
            html = path.read_text()
        else:
            try:
                response = http.get(session, url, expect="text/html")
            except http.FetchError as error:
                print(f"    {DOCUMENTS}: {park['id']} page failed ({error})")
                continue
            html = response.text
            path.write_text(html)
            record.add_request(url)
            record.add_file(path, root=directory)
        entry: dict[str, Any] = {"page": url, "documents": []}
        seen: set[str] = set()
        for link in pdf_links(url, html):
            if link["url"] not in heads:
                heads[link["url"]] = shared._head(session, link["url"])
                record.add_request(link["url"], {"method": "HEAD"})
            head = heads[link["url"]]
            final = head.get("url") or link["url"]
            if not head.get("ok") or final in seen:
                continue
            seen.add(final)
            document: dict[str, Any] = {"title": shared.document_title(link), "url": final}
            if head.get("bytes"):
                document["bytes"] = head["bytes"]
            entry["documents"].append(document)
        links[park["id"]] = entry
        time.sleep(http.DEFAULT_POLITENESS.pause_seconds)
    heads_path.write_text(json.dumps(heads, ensure_ascii=False, indent=1))
    links_path = directory / "links.json"
    links_path.write_text(json.dumps(links, ensure_ascii=False, indent=1))
    record.add_file(links_path, root=directory)
    _write_record(record, directory)
    documents = sum(len(entry["documents"]) for entry in links.values())
    print(f"    {DOCUMENTS}: {len(links)} park pages, {documents} PDFs that answer")


# MARK: - OpenStreetMap


def as_out_geom(elements: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Train route relations from an extract read, in Overpass's ``out geom`` shape: each
    way member with its ``geometry`` and each node member with its ``lat`` and ``lon``, as
    Norway's rail layer reads them (``no.transport.Route``)."""
    ways = {e["id"]: e for e in elements if e.get("type") == "way"}
    nodes = {e["id"]: e for e in elements if e.get("type") == "node"}
    routes = []
    for element in elements:
        if element.get("type") != "relation" or (element.get("tags") or {}).get(
            "route"
        ) != "train":
            continue
        members = []
        for member in element.get("members") or []:
            entry = dict(member)
            if member.get("type") == "way" and member.get("ref") in ways:
                entry["geometry"] = ways[member["ref"]].get("geometry") or []
            elif member.get("type") == "node" and member.get("ref") in nodes:
                entry["lat"] = nodes[member["ref"]]["lat"]
                entry["lon"] = nodes[member["ref"]]["lon"]
            members.append(entry)
        routes.append({**element, "members": members})
    return routes


def _fetch_osm(
    version: str, outlines: dict[str, list[outline.Polygon]], *, refresh: bool
) -> None:
    """Rail and stations, and the trails of any park DOC Tracks leaves without one, read
    out of Geofabrik's New Zealand extract in one pass. The extract is downloaded only
    while one of those files is missing."""
    from ..abroad import trails as abroad_trails

    directory = rawstore.version_directory(OSM, version)
    rail_path, stations_path = directory / RAIL_FILE, directory / STATIONS_FILE
    want_rail = refresh or rawstore.latest(OSM, RAIL_FILE) is None
    features = tracks.read_features()
    trail_source = abroad_trails.OSM_TRAIL_SOURCES["nz"]
    trailless = [
        (park, outlines[park["id"]])
        for park in content.parks()
        if park["id"] in outlines
        and not tracks.routes(park, features, outlines[park["id"]])
        and (refresh or rawstore.latest(trail_source, f"{park['id']}.json") is None)
    ]
    if not want_rail and not trailless:
        print(f"    {OSM}: rail and trails already read from an extract")
        return
    extract = osm_pbf.extract_for("nz")
    path = None if refresh else osm_pbf.latest(extract.source, extract.filename)
    if path is None:
        print(f"    {OSM}: downloading {extract.url}", flush=True)
        path = osm_pbf.download(
            rawstore.version_directory(extract.source, version),
            url=extract.url, filename=extract.filename, refresh=refresh,
        )
    requests: list[osm_pbf.Request] = []
    if want_rail:
        requests.append(osm_pbf.Request(name="rail", rail=RAIL_BOX, stations=RAIL_BOX))
    for park, polygons in trailless:
        if (request := abroad_trails.extract_request(park, polygons)) is not None:
            request.name = f"trails:{park['id']}"
            requests.append(request)
    print(f"    {OSM}: reading {len(requests)} selections out of {path.name}", flush=True)
    selected = osm_pbf.select(path, requests)
    described = osm_pbf.describe(path)
    if want_rail:
        header = {
            "version": 0.6,
            "generator": f"unigrids-pipeline {__version__} from {path.name}",
            "osm3s": {"timestamp_osm_base": described.get("replicationTimestamp", "")},
        }
        elements = selected["rail"]
        routes = as_out_geom(elements)
        stations = [e for e in elements if e.get("type") == "node" and e.get("tags")]
        record = FetchRecord(source=OSM_TERMS, fetched_at=rawstore.utc_now())
        osm_pbf.write_elements(rail_path, routes, **header)
        osm_pbf.write_elements(stations_path, stations, **header)
        record.add_request(described["url"], {**described, "rail": RAIL_BOX},
                           elements=len(elements))
        record.add_file(rail_path, root=directory)
        record.add_file(stations_path, root=directory)
        _write_record(record, directory)
        print(f"    {OSM}: {len(routes)} train routes, {len(stations)} station nodes")
    if trailless:
        abroad_trails.fetch_osm_extract(
            "nz", trailless, version, path,
            selected={
                park["id"]: selected[f"trails:{park['id']}"] for park, _ in trailless
                if f"trails:{park['id']}" in selected
            },
        )


# MARK: - Climate


def _fetch_climate(
    session: httpx.Client, version: str, areas: dict[str, Area], *, refresh: bool
) -> None:
    points = {
        park["id"]: centre
        for park, area in national_parks(areas)
        if area is not None and (centre := area.centre) is not None
    }
    climate.fetch_points(points, version, source=CLIMATE, refresh=refresh, session=session)
