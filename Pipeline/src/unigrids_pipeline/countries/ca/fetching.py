"""Fetching Canada's sources into the date-versioned raw store.

Every source lands in ``raw/<date>/ca-<source>/`` with a ``source.json`` beside it, and
every step resumes where an earlier run stopped: a file already in today's snapshot is left
alone unless ``refresh`` asks otherwise.

``ca-cpcad/``
    The Canadian Protected and Conserved Areas Database (OGL–Canada): Parks Canada's
    records of the 48 national parks and the five marine conservation areas, and every
    provincial and territorial park record, its outline fetched where its park reaches
    100 km², all in WGS84.
``ca-pc-trails/``
    Parks Canada's trails layer, whole (OGL–Canada).
``ca-pc-facilities/``
    Parks Canada's facilities (visitor centres, campgrounds, backcountry camping and
    shelter areas, warming huts, trailheads) and accommodation (every campsite, oTENTik,
    cabin and backcountry hut) layers (OGL–Canada).
``ca-attendance/``
    Parks Canada's attendance table for the latest fiscal year (OGL–Canada).
``ca-wikidata/``, ``ca-wikipedia/``, ``ca-commons/``, ``ca-photos/``
    Canada's protected areas on Wikidata, English Wikipedia leads for the second tier,
    Commons licence metadata for every photograph a guide or item names, and the guides'
    photographs themselves.
``ca-documents/``
    Each national park's page on parks.canada.ca, its "Plan your visit" page and the
    brochure and map pages that links, and the PDFs they link, each checked with HEAD.
``ca-osm/``
    VIA Rail's routes and the stations near the parks, and huts in and beside the parks,
    read out of Geofabrik's provincial and territorial extracts (ODbL) one at a time, each
    deleted once read; ``ca-osm-trails/`` holds the trails of parks Parks Canada's layer
    leaves without one.
``ca-climate/``
    Ten years of Open-Meteo daily weather at each park's centre (``climate``).

Requests identify the app and nothing else, and pause between calls.
"""

from __future__ import annotations

import csv
import html as html_lib
import io
import json
import re
import shutil
import time
from pathlib import Path
from typing import Any
from urllib.parse import urljoin

import httpx

from ... import __version__, climate, config, geo, outline, rawstore
from ...rawstore import FetchRecord, SourceTerms
from ...sources import http, osm_pbf
from ..common import photo_filename
from ..no import fetching as shared
from . import content, pctrails, rules, wiki

USER_AGENT = shared.USER_AGENT

# Raw store sources.
CPCAD = "ca-cpcad"
TRAILS = pctrails.SOURCE
FACILITIES = "ca-pc-facilities"
ATTENDANCE = "ca-attendance"
WIKIDATA = "ca-wikidata"
WIKIPEDIA = "ca-wikipedia"
COMMONS = "ca-commons"
PHOTOS = "ca-photos"
DOCUMENTS = "ca-documents"
OSM = "ca-osm"
CLIMATE = "ca-climate"

# MARK: - Endpoints and terms

CPCAD_LAYER = "https://maps-cartes.ec.gc.ca/arcgis/rest/services/CWS_SCF/CPCAD/MapServer/0"
PC_SERVICES = "https://services2.arcgis.com/wCOMu5IS7YdSyPNx/arcgis/rest/services"
TRAILS_LAYER = (
    f"{PC_SERVICES}/Trails_Sentiers_APCA_Temporary_Temporaire_APCA_OpenOuvert/FeatureServer/0"
)
FACILITIES_LAYER = f"{PC_SERVICES}/Facilities_Installations_Point_OpenData/FeatureServer/0"
ACCOMMODATION_LAYER = f"{PC_SERVICES}/Accommodation_Hebergement_APCA_OpenOuvert/FeatureServer/0"

CPCAD_FIELDS = (
    "OBJECTID,NAME_E,NAME_F,NAME_IND,TYPE_E,ESTYEAR,LOC,O_AREA_HA,STATUS,PARENT_ID,ZONE_ID,"
    "ZONEDESC_E,MGMT_E,PROVIDER,BIOME"
)
EXPECTED_NATIONAL_PARKS = 48

OGL = "Open Government Licence – Canada"
CPCAD_ATTRIBUTION = (
    "Contains information licensed under the Open Government Licence – Canada "
    "(Environment and Climate Change Canada, Canadian Protected and Conserved Areas Database)"
)
PC_ATTRIBUTION = (
    "Contains information licensed under the Open Government Licence – Canada (Parks Canada)"
)

CPCAD_TERMS = SourceTerms(
    identifier="ca-cpcad",
    title="Canadian Protected and Conserved Areas Database (CPCAD): national parks, national "
    "marine conservation areas and provincial and territorial parks",
    url=CPCAD_LAYER,
    licence=OGL,
    attribution=CPCAD_ATTRIBUTION,
    notes="Geometry in WGS84 (outSR 4326), generalised by the service to about 10 m for the "
    "national parks and 50 m for the rest (maxAllowableOffset), then simplified by Unigrids "
    "before it ships.",
)
TRAIL_TERMS = SourceTerms(
    identifier="ca-pc-trails",
    title="Parks Canada trails (Trails APCA, the open layer of the 2025 migration)",
    url=TRAILS_LAYER,
    licence=OGL,
    attribution=PC_ATTRIBUTION,
    notes="Every record in WGS84. The layer repeats a line once per activity; the build keeps "
    "named hiking records inside a national park. Open-data record: "
    + rules.TRAILS_DATASET_URL,
)
FACILITY_TERMS = SourceTerms(
    identifier="ca-pc-facilities",
    title="Parks Canada facilities (points) and accommodation",
    url=PC_SERVICES,
    licence=OGL,
    attribution=PC_ATTRIBUTION,
    notes="Facilities: https://open.canada.ca/data/en/dataset/"
    "3969368d-33b5-47c8-8953-f31b15d8e007; accommodation: "
    "https://open.canada.ca/data/en/dataset/74054d44-68cf-41af-8919-5f09f80dcd02.",
)
ATTENDANCE_TERMS = SourceTerms(
    identifier="ca-attendance",
    title="Parks Canada attendance 2025-26",
    url=f"https://open.canada.ca/data/en/dataset/{rules.ATTENDANCE_DATASET}",
    licence=OGL,
    attribution=PC_ATTRIBUTION,
    notes=f"Counts for {rules.attendance_period()}. 'UR' (under review) is not a count.",
)
WIKIDATA_TERMS = SourceTerms(
    identifier="ca-wikidata",
    title="Wikidata: Canada's protected areas and parks",
    url=shared.SPARQL,
    licence="CC0",
    attribution="Wikidata",
    notes="Used for each place's English Wikipedia article, P18 image and Commons category.",
)
WIKIPEDIA_TERMS = SourceTerms(
    identifier="ca-wikipedia",
    title="English Wikipedia leads (Action API, intro extracts) for Canada's marine "
    "conservation areas and provincial and territorial parks",
    url=shared.WIKIPEDIA_API,
    licence="CC BY-SA 4.0",
    attribution="Summaries: Wikipedia, CC BY-SA 4.0, linked from each place",
)
COMMONS_TERMS = SourceTerms(
    identifier="ca-commons",
    title="Wikimedia Commons licence and author metadata",
    url=shared.COMMONS_API,
    licence="Per file",
    attribution="Photographs credited individually, via Wikimedia Commons",
    notes="Every photograph keeps its credit and licence, and is marked public domain only "
    "when its licence says so. Parks Canada's own photographs are not used.",
)
PHOTO_TERMS = SourceTerms(
    identifier="ca-photos",
    title="Wikimedia Commons photographs named in Canada's guides",
    url=shared.COMMONS_FILE_PATH,
    licence="Per file (see ca-commons/licences.json)",
    attribution="Photographs credited individually, via Wikimedia Commons",
    notes=f"Downloaded at {shared.PHOTO_WIDTH} px wide and resized by the build.",
)
DOCUMENT_TERMS = SourceTerms(
    identifier="ca-documents",
    title="Parks Canada national park pages on parks.canada.ca and the PDFs they link",
    url="https://parks.canada.ca/pn-np",
    licence="Crown copyright; links only, nothing is extracted",
    attribution="Parks Canada",
    notes="Each park's page, its 'Plan your visit' page and the brochure, guide and map pages "
    "that links, read as HTML; every PDF checked with HEAD.",
)
OSM_TERMS = SourceTerms(
    identifier="openstreetmap-ca",
    title="OpenStreetMap from Geofabrik's provincial extracts: VIA Rail, stations and huts",
    url="https://www.openstreetmap.org/copyright",
    licence="Open Database License (ODbL) 1.0",
    attribution="© OpenStreetMap contributors",
    notes="route=train relations with their member ways and stops, railway stations, and "
    "tourism=alpine_hut|wilderness_hut in and beside each national park, read out of each "
    "province's and territory's .osm.pbf in turn and written in Overpass's shapes; a route "
    "crossing provinces is joined from each extract's part. Shipped as data: a Derivative "
    "Database under the ODbL.",
)

# South, west, north, east: all of Canada, for the rail selection.
RAIL_BOX = (41.6, -141.1, 83.2, -52.5)
RAIL_FILE = "rail-routes-ca.json"
STATIONS_FILE = "stations.json"
HUTS_FILE = "huts.json"
# The provinces VIA Rail runs through: their extracts are read for rail as well as huts.
RAIL_PROVINCES = ("BC", "AB", "SK", "MB", "ON", "QC", "NB", "NS")
# Generous boxes around each province and territory (south, west, north, east), to know
# which extracts a park's box reaches into.
PROVINCE_BOXES: dict[str, tuple[float, float, float, float]] = {
    "AB": (48.9, -120.1, 60.1, -109.9), "BC": (48.2, -139.2, 60.1, -114.0),
    "MB": (48.9, -102.1, 60.1, -88.9), "NB": (44.5, -69.1, 48.1, -63.7),
    "NL": (46.5, -67.9, 60.5, -52.5), "NT": (59.9, -136.5, 78.8, -101.9),
    "NS": (43.3, -66.4, 47.1, -59.6), "NU": (51.6, -121.0, 83.2, -61.0),
    "ON": (41.6, -95.2, 56.9, -74.3), "PE": (45.9, -64.5, 47.1, -61.9),
    "QC": (44.9, -79.8, 62.6, -57.1), "SK": (48.9, -110.1, 60.1, -101.3),
    "YT": (59.9, -141.1, 69.7, -123.8),
}
LOW_DISK_BYTES = 3 * 1024**3
"""Below this much free space the fetch stops rather than fill the disk."""


def client() -> httpx.Client:
    return shared.client()


def _skip(path: Path, refresh: bool) -> bool:
    return path.exists() and not refresh


def _write_record(record: FetchRecord, directory: Path) -> None:
    shared._write_record(record, directory)


def _collection(features: list[dict[str, Any]]) -> str:
    return json.dumps({"type": "FeatureCollection", "features": features}, ensure_ascii=False)


def free_bytes() -> int:
    return shutil.disk_usage(config.RAW_DIR if config.RAW_DIR.exists() else Path.home()).free


def _check_disk(step: str) -> None:
    if free_bytes() < LOW_DISK_BYTES:
        raise SystemExit(
            f"    {step}: under {LOW_DISK_BYTES / 1024**3:.0f} GB free; stopping. Free space "
            "and run again to resume."
        )


# MARK: - Fetch


def fetch(*, refresh: bool = False) -> Path:
    """Fetch everything Canada's ``assemble`` reads into ``raw/<today>/``. Returns the
    version directory."""
    version = rawstore.today()
    root = rawstore.version_directory(CPCAD, version).parent
    with client() as session:
        _fetch_cpcad(session, version, refresh=refresh)
        areas = read_areas(root / CPCAD)
        _fetch_layer(session, version, TRAILS, pctrails.FILE, TRAILS_LAYER, TRAIL_TERMS,
                     refresh=refresh, page_size=1000)
        _fetch_facilities(session, version, refresh=refresh)
        _fetch_attendance(session, version, refresh=refresh)
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
    # Trails: Parks Canada's for every park, OpenStreetMap for any it leaves without one;
    # then the elevation tiles the kept routes cross, and each park's range, kept so the
    # tiles can go.
    from ..abroad import elevation as abroad_elevation
    from ..abroad import trails as abroad_trails

    abroad_trails.fetch("ca", list(content.parks()), outlines, refresh=False)
    _check_disk("elevation")
    places = [{"id": park_id, "kind": "nationalPark"} for park_id in outlines]
    abroad_elevation.attach_extremes(places, outlines, online=True)
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


# MARK: - CPCAD


def _parents_where(parents: list[int]) -> str:
    return f"PROVIDER = {rules.PARKS_CANADA} AND PARENT_ID IN ({','.join(map(str, parents))})"


def provincial_where() -> str:
    types = ",".join("'" + name.replace("'", "''") + "'" for name in rules.PROVINCIAL_TYPES)
    return f"TYPE_E IN ({types})"


def _fetch_cpcad(session: httpx.Client, version: str, *, refresh: bool) -> None:
    directory = rawstore.version_directory(CPCAD, version)
    record = FetchRecord(source=CPCAD_TERMS, fetched_at=rawstore.utc_now())
    parks = sorted(int(park["cpcadParentId"]) for park in content.parks())
    marine = sorted(rules.MARINE_CONSERVATION_AREAS)
    queries = {
        "national-parks.geojson": (_parents_where(parks), "0.0001", 4),
        "marine-areas.geojson": (_parents_where(marine), "0.0005", 2),
    }
    for name, (where, offset, page) in queries.items():
        path = directory / name
        if _skip(path, refresh):
            print(f"    {CPCAD}/{name}: already fetched today")
            continue
        features = arcgis_query(
            session, CPCAD_LAYER,
            {"where": where, "outFields": CPCAD_FIELDS, "orderByFields": "OBJECTID",
             "maxAllowableOffset": offset},
            record=record, page_size=page,
        )
        path.write_text(_collection(features))
        record.add_file(path, root=directory)
        print(f"    {CPCAD}/{name}: {len(features)} records")
    # Every provincial park record without its outline, to find the parks of 100 km² or
    # more by their official area, then the outlines of those alone.
    index_path = directory / "provincial-index.json"
    if not _skip(index_path, refresh):
        rows = arcgis_query(
            session, CPCAD_LAYER,
            {"where": provincial_where(), "outFields": CPCAD_FIELDS,
             "orderByFields": "OBJECTID", "returnGeometry": "false"},
            record=record, page_size=2000,
        )
        index_path.write_text(json.dumps(
            [row.get("properties") or {} for row in rows], ensure_ascii=False
        ))
        record.add_file(index_path, root=directory)
        print(f"    {CPCAD}/provincial-index.json: {len(rows)} records")
    provincial_path = directory / "provincial-parks.geojson"
    if not _skip(provincial_path, refresh):
        wanted = provincial_parents(json.loads(index_path.read_text()))
        features: list[dict[str, Any]] = []
        for start in range(0, len(wanted), 40):
            chunk = wanted[start:start + 40]
            features.extend(arcgis_query(
                session, CPCAD_LAYER,
                {"where": f"{provincial_where()} AND PARENT_ID IN ({','.join(map(str, chunk))})",
                 "outFields": CPCAD_FIELDS, "orderByFields": "OBJECTID",
                 "maxAllowableOffset": "0.0005"},
                record=record, page_size=5,
            ))
        provincial_path.write_text(_collection(features))
        record.add_file(provincial_path, root=directory)
        print(f"    {CPCAD}/provincial-parks.geojson: {len(features)} records of "
              f"{len(wanted)} parks")
    _write_record(record, directory)


def provincial_parents(rows: list[dict[str, Any]]) -> list[int]:
    """The ``PARENT_ID`` of every provincial or territorial park whose records' official
    areas come to 100 km² or more."""
    totals: dict[int, float] = {}
    for row in rows:
        parent = row.get("PARENT_ID")
        if not isinstance(parent, int | float) or not rules.is_provincial_park(row):
            continue
        totals[int(parent)] = totals.get(int(parent), 0.0) + (rules.official_hectares(row) or 0.0)
    return sorted(parent for parent, total in totals.items() if total >= rules.MINIMUM_HECTARES)


class Area:
    """One place's CPCAD records as fetched: their properties and outline."""

    def __init__(self, key: int, tier: str) -> None:
        self.key = key
        self.tier = tier
        self.polygons: list[outline.Polygon] = []
        self.parts: list[dict[str, Any]] = []
        self._centre: tuple[float, float] | None = None
        self._centre_known = False

    @property
    def parent_id(self) -> str:
        return str(self.key)

    def add(self, feature: dict[str, Any]) -> None:
        self.polygons.extend(outline.polygons_of(feature.get("geometry")))
        self.parts.append(feature.get("properties") or {})
        self._centre_known = False

    @property
    def main(self) -> dict[str, Any]:
        """The largest record, whose name and designation the place takes."""
        return max(self.parts, key=lambda part: (rules.official_hectares(part) or 0.0,
                                                 -(part.get("OBJECTID") or 0)))

    @property
    def name(self) -> str:
        return re.sub(r"\s+", " ", self.main.get("NAME_E") or "").strip()

    @property
    def official_hectares(self) -> float | None:
        values = [rules.official_hectares(part) for part in self.parts]
        if not values or any(value is None for value in values):
            return None
        return round(sum(value for value in values if value is not None), 1)

    def subdivisions(self) -> list[str]:
        """The provinces and territories its records lie in, largest share first, as
        ``CA-XX``; a marine record names none."""
        shares: dict[str, float] = {}
        for part in self.parts:
            if code := rules.iso_code(part.get("LOC")):
                shares[code] = shares.get(code, 0.0) + (rules.official_hectares(part) or 0.0)
        ordered = sorted(shares, key=lambda code: (-shares[code], code))
        return [rules.subdivision(code) for code in ordered]

    @property
    def centre(self) -> tuple[float, float] | None:
        if not self._centre_known:
            self._centre = outline.label_point(self.polygons)
            self._centre_known = True
        return self._centre

    @property
    def box(self) -> geo.BoundingBox | None:
        found = outline.bbox(self.polygons)
        if found is None:
            return None
        south, west, north, east = found
        return geo.BoundingBox(west=west, south=south, east=east, north=north)

    @property
    def reach_km(self) -> float:
        found = outline.bbox(self.polygons)
        if found is None:
            return 0.0
        south, west, north, east = found
        return wiki.distance_km((south, west), (north, east)) / 2


def read_areas(directory: Path | None) -> dict[str, Area]:
    """``<tier>:<PARENT_ID>`` → the place's records, for every national park (``np``),
    marine area (``mca``) and provincial park (``pp``) fetched."""
    areas: dict[str, Area] = {}
    if directory is None:
        return areas
    sources = (
        ("national-parks.geojson", "np", rules.NATIONAL_PARK_TYPES),
        ("marine-areas.geojson", "mca", rules.MARINE_TYPES),
        ("provincial-parks.geojson", "pp", frozenset(rules.PROVINCIAL_TYPES)),
    )
    for name, tier, types in sources:
        path = directory / name
        if not path.exists():
            continue
        for feature in json.loads(path.read_text()).get("features") or []:
            properties = feature.get("properties") or {}
            parent = properties.get("PARENT_ID")
            if properties.get("TYPE_E") not in types or not isinstance(parent, int | float):
                continue
            if tier != "pp" and properties.get("PROVIDER") != rules.PARKS_CANADA:
                continue
            if properties.get("STATUS") == 0:  # delisted
                continue
            key = f"{tier}:{int(parent)}"
            areas.setdefault(key, Area(int(parent), tier)).add(feature)
    return _join_namesakes(areas)


def _join_namesakes(areas: dict[str, Area]) -> dict[str, Area]:
    """One provincial park CPCAD files under two parents — Yukon's Ni'iinlii Njik (Fishing
    Branch), its ecological reserve and its wilderness preserve — joined under the lower,
    when the name, designation and province are the same. Parks that share a name across a
    border (Cypress Hills, Duck Mountain) stay two."""
    by_name: dict[tuple[str, str, Any], Area] = {}
    for key in sorted(areas, key=lambda key: areas[key].key):
        area = areas[key]
        if area.tier != "pp":
            continue
        name = (area.name.lower(), area.main.get("TYPE_E"), area.main.get("LOC"))
        if (first := by_name.get(name)) is None:
            by_name[name] = area
            continue
        first.polygons.extend(area.polygons)
        first.parts.extend(area.parts)
        first._centre_known = False
        del areas[key]
    return areas


def national_parks(areas: dict[str, Area]) -> list[tuple[dict[str, Any], Area | None]]:
    """Each park in the content list with its CPCAD records."""
    return [(park, areas.get(f"np:{int(park['cpcadParentId'])}")) for park in content.parks()]


def marine_areas(areas: dict[str, Area]) -> list[Area]:
    return [areas[key] for key in sorted(areas) if areas[key].tier == "mca"]


def second_tier(areas: dict[str, Area]) -> list[Area]:
    """Every provincial and territorial park of 100 km² or more, by official area, in
    parent order so identifiers are minted the same way every run."""
    chosen = [
        area for area in areas.values()
        if area.tier == "pp" and (area.official_hectares or 0.0) >= rules.MINIMUM_HECTARES
    ]
    return sorted(chosen, key=lambda area: area.key)


# MARK: - Parks Canada's layers


def _fetch_layer(
    session: httpx.Client,
    version: str,
    source: str,
    filename: str,
    layer: str,
    terms: SourceTerms,
    *,
    refresh: bool,
    page_size: int,
) -> None:
    directory = rawstore.version_directory(source, version)
    path = directory / filename
    if _skip(path, refresh):
        print(f"    {source}/{filename}: already fetched today")
        return
    record = FetchRecord(source=terms, fetched_at=rawstore.utc_now())
    features = arcgis_query(
        session, layer, {"where": "1=1", "outFields": "*", "orderByFields": "OBJECTID"},
        record=record, page_size=page_size,
    )
    path.write_text(_collection(features))
    record.add_file(path, root=directory)
    _write_record(record, directory)
    print(f"    {source}/{filename}: {len(features)} records")


def _fetch_facilities(session: httpx.Client, version: str, *, refresh: bool) -> None:
    for filename, layer in (("facilities.geojson", FACILITIES_LAYER),
                            ("accommodation.geojson", ACCOMMODATION_LAYER)):
        _fetch_layer(session, version, FACILITIES, filename, layer, FACILITY_TERMS,
                     refresh=refresh, page_size=2000)


def read_layer(directory: Path | None, name: str) -> list[dict[str, Any]]:
    if directory is None or not (directory / name).exists():
        return []
    return json.loads((directory / name).read_text()).get("features") or []


def _fetch_attendance(session: httpx.Client, version: str, *, refresh: bool) -> None:
    directory = rawstore.version_directory(ATTENDANCE, version)
    path = directory / "attendance.csv"
    if _skip(path, refresh):
        return
    record = FetchRecord(source=ATTENDANCE_TERMS, fetched_at=rawstore.utc_now())
    response = http.get(session, rules.ATTENDANCE_URL)
    path.write_bytes(response.content)
    record.add_request(rules.ATTENDANCE_URL)
    record.add_file(path, root=directory)
    _write_record(record, directory)
    print(f"    {ATTENDANCE}: {len(read_attendance(directory))} places counted")


def read_attendance(directory: Path | None) -> dict[str, int]:
    """Place → count from the attendance table, which Parks Canada saves as Windows-1252."""
    if directory is None or not (directory / "attendance.csv").exists():
        return {}
    raw = (directory / "attendance.csv").read_bytes()
    try:
        text = raw.decode("utf-8-sig")
    except UnicodeDecodeError:
        text = raw.decode("cp1252")
    return rules.attendance(list(csv.reader(io.StringIO(text))))


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


def place_name(area: Area) -> tuple[str, str]:
    """``(name, designation)`` a marine area or provincial park is shown under."""
    if area.tier == "mca":
        return rules.MARINE_CONSERVATION_AREAS.get(area.key, (area.name, "Marine Park"))
    return rules.display_name(area.name, area.main.get("TYPE_E") or "")


def _match_tier(area: Area) -> str:
    if area.tier == "pp" and area.main.get("TYPE_E") == "Quebec's national park":
        return "ppqc"
    return area.tier


def wiki_matches(
    areas: dict[str, Area], others: list[dict[str, Any]]
) -> dict[str, dict[str, Any]]:
    """``<tier>:<PARENT_ID>`` → the Wikidata item that is the place's own, the national
    parks matched with the rest so a park's item is never a neighbour's."""
    places = [
        (f"np:{area.key}", "np", park["name"], area.centre, area.reach_km)
        for park, area in national_parks(areas) if area is not None
    ]
    places.extend(
        (f"{area.tier}:{area.key}", _match_tier(area), place_name(area)[0], area.centre,
         area.reach_km)
        for area in [*marine_areas(areas), *second_tier(areas)]
    )
    return wiki.own_matches(places, others)


def second_tier_matches(
    wikidata_dir: Path, areas: dict[str, Area]
) -> dict[str, dict[str, Any]]:
    found = wiki_matches(areas, read_candidates(wikidata_dir))
    chosen = [*marine_areas(areas), *second_tier(areas)]
    keys = [f"{area.tier}:{area.key}" for area in chosen]
    matches = {key: found[key] for key in keys if key in found}
    with_article = sum(1 for item in matches.values() if item.get("article"))
    print(
        f"    {WIKIDATA}: {len(matches)} of {len(chosen)} marine areas and provincial parks "
        f"matched, {with_article} with an English article"
    )
    return matches


def _load(path: Path, refresh: bool) -> dict[str, Any]:
    if refresh or not path.exists():
        return {}
    return json.loads(path.read_text())


def _fetch_wikipedia(
    session: httpx.Client, version: str, matches: dict[str, dict[str, Any]], *, refresh: bool
) -> None:
    """The English lead of each matched article, twenty to a request."""
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
    """Licence and author for every photograph a guide names and every second-tier
    place's P18 image, fifty files to a request."""
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
                "description": (meta.get("ImageDescription") or {}).get("value"),
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
_HEADING = re.compile(r"<(strong|h[2-5])\b[^>]*>(.*?)</\1>", re.IGNORECASE | re.DOTALL)
_GENERIC = re.compile(r"^(?:download(?: the)?(?: pdf)?(?: brochure| version| file| map)?|pdf|"
                      r"here|click here|read more|view)$", re.IGNORECASE)
# A park's pages that hold its brochures, guides and maps, as its "Plan your visit" page
# links them: /visit/brochures, /visit/depliants-brochures, /visit/cartes-maps, …
_DOCUMENT_PAGE = re.compile(
    r"/visit/(?:[a-z0-9-]*brochure[a-z0-9-]*|[a-z0-9-]*maps?|guides?|prospectus[a-z0-9-]*)$"
)


def _text(fragment: str) -> str:
    return re.sub(r"\s+", " ", html_lib.unescape(re.sub(r"<[^>]+>", " ", fragment))).strip()


def pdf_links(page_url: str, html: str) -> list[dict[str, str]]:
    """Every English PDF a Parks Canada page links, absolute, once each, titled by the
    link's text or, where that only says "Download PDF", by the heading just before it."""
    found: list[dict[str, str]] = []
    seen: set[str] = set()
    for match in _ANCHOR.finditer(html):
        href, text = match.group(1), match.group(2)
        url = urljoin(page_url, href.strip().replace("&amp;", "&"))
        label = re.sub(r"\s*\(\s*(?:PDF\b)?[^)]*\b[KMG]?B\s*\)\s*$", "", _text(text),
                       flags=re.IGNORECASE).strip()
        label = re.sub(r"\s*\(PDF[^)]*\)\s*$", "", label, flags=re.IGNORECASE).strip()
        if not label or _GENERIC.match(label):
            before = html[max(0, match.start() - 1500):match.start()]
            headings = [_text(heading) for _, heading in _HEADING.findall(before)]
            label = next((heading for heading in reversed(headings) if heading), "")
        if url in seen or rules.is_french(url, label):
            continue
        seen.add(url)
        found.append({"title": label, "url": url})
    return found


def document_pages(visit_url: str, html: str) -> list[str]:
    """The brochure, guide and map pages a park's "Plan your visit" page links."""
    pages: list[str] = []
    for href in re.findall(r"""href=["']([^"'#?]+)["']""", html):
        url = urljoin(visit_url, href.strip()).rstrip("/")
        inside = url.startswith(visit_url.rstrip("/") + "/")
        if inside and _DOCUMENT_PAGE.search(url) and url not in pages:
            pages.append(url)
    return pages


def _page(
    session: httpx.Client, url: str, path: Path, record: FetchRecord, refresh: bool
) -> str | None:
    if _skip(path, refresh):
        return path.read_text()
    try:
        response = http.get(session, url, expect="text/html")
    except http.FetchError as error:
        print(f"    {DOCUMENTS}: {url} failed ({error})")
        return None
    path.write_text(response.text)
    record.add_request(url)
    record.add_file(path, root=path.parent.parent)
    return response.text


def _fetch_documents(session: httpx.Client, version: str, *, refresh: bool) -> None:
    directory = rawstore.version_directory(DOCUMENTS, version)
    pages_dir = directory / "pages"
    pages_dir.mkdir(exist_ok=True)
    record = FetchRecord(source=DOCUMENT_TERMS, fetched_at=rawstore.utc_now())
    heads_path = directory / "heads.json"
    heads: dict[str, Any] = _load(heads_path, refresh)
    links: dict[str, Any] = {}
    for park in content.parks():
        home = park.get("pcPage")
        if not home:
            continue
        visit = f"{home}/visit"
        sources = [(home, pages_dir / f"{park['id']}.html")]
        visit_html = _page(session, visit, pages_dir / f"{park['id']}-visit.html", record, refresh)
        if visit_html:
            sources.append((visit, pages_dir / f"{park['id']}-visit.html"))
            for index, url in enumerate(document_pages(visit, visit_html)):
                sources.append((url, pages_dir / f"{park['id']}-documents-{index}.html"))
        entry: dict[str, Any] = {"page": home, "documents": []}
        seen: set[str] = set()
        for url, path in sources:
            html = _page(session, url, path, record, refresh)
            if not html:
                continue
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
            time.sleep(http.DEFAULT_POLITENESS.pause_seconds)
        links[park["id"]] = entry
    heads_path.write_text(json.dumps(heads, ensure_ascii=False, indent=1))
    links_path = directory / "links.json"
    links_path.write_text(json.dumps(links, ensure_ascii=False, indent=1))
    record.add_file(links_path, root=directory)
    _write_record(record, directory)
    documents = sum(len(entry["documents"]) for entry in links.values())
    print(f"    {DOCUMENTS}: {len(links)} park pages, {documents} PDFs that answer")


# MARK: - OpenStreetMap


def as_out_geom(elements: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Train route relations from an extract read, in Overpass's ``out geom`` shape."""
    from ..nz import fetching as new_zealand

    return new_zealand.as_out_geom(elements)


def merge_routes(parts: list[list[dict[str, Any]]]) -> list[dict[str, Any]]:
    """One route per relation from each extract's part of it: a member a province's
    extract carries with its geometry or position fills in what another's lacks."""
    merged: dict[int, dict[str, Any]] = {}
    for routes in parts:
        for route in routes:
            known = merged.get(route["id"])
            if known is None:
                merged[route["id"]] = json.loads(json.dumps(route))
                continue
            for mine, theirs in zip(known["members"], route["members"], strict=False):
                if (mine.get("type"), mine.get("ref")) != (theirs.get("type"), theirs.get("ref")):
                    continue
                for key in ("geometry", "lat", "lon"):
                    if key not in mine and key in theirs:
                        mine[key] = theirs[key]
    return [merged[key] for key in sorted(merged)]


def _merge_elements(parts: list[list[dict[str, Any]]]) -> list[dict[str, Any]]:
    """Each element once; a relation two extracts both carry keeps every member geometry
    either gives (a hiking route across the Alberta–British Columbia line)."""
    relations = merge_routes([
        [element for element in elements if element.get("type") == "relation"]
        for elements in parts
    ])
    found: dict[tuple[str, int], dict[str, Any]] = {
        ("relation", relation["id"]): relation for relation in relations
    }
    for elements in parts:
        for element in elements:
            found.setdefault((element["type"], element["id"]), element)
    return [found[key] for key in sorted(found)]


def provinces_for(box: geo.BoundingBox) -> list[str]:
    """The provinces and territories whose extracts a box reaches into."""
    return [
        code for code, (south, west, north, east) in PROVINCE_BOXES.items()
        if box.south <= north and box.north >= south and box.west <= east and box.east >= west
    ]


def _fetch_osm(
    version: str, outlines: dict[str, list[outline.Polygon]], *, refresh: bool
) -> None:
    """Rail, stations, huts and the trails of any park Parks Canada's layer leaves without
    one, read out of each province's extract in turn. An extract is downloaded only while
    a province's selection is missing, and deleted as soon as it has been read."""
    from ..abroad import trails as abroad_trails

    directory = rawstore.version_directory(OSM, version)
    parts_dir = directory / "provinces"
    parts_dir.mkdir(exist_ok=True)
    features = pctrails.read_features()
    trail_source = abroad_trails.OSM_TRAIL_SOURCES["ca"]
    trailless = [
        park for park in content.parks()
        if park["id"] in outlines
        and abroad_trails.is_thin("ca", pctrails.routes(park, features, outlines[park["id"]]))
        and (refresh or rawstore.latest(trail_source, f"{park['id']}.json") is None)
    ]
    boxes = {
        park_id: abroad_trails._search_box(polygons) for park_id, polygons in outlines.items()
    }
    # Huts beside a park are looked for a little beyond it, as its box is.
    wanted: dict[str, list[osm_pbf.Request]] = {}
    for code in osm_pbf.CANADA_PROVINCES:
        requests: list[osm_pbf.Request] = []
        if code in RAIL_PROVINCES:
            requests.append(osm_pbf.Request(name="rail", rail=RAIL_BOX, stations=RAIL_BOX))
        for park_id, box in boxes.items():
            if box is None or code not in provinces_for(box):
                continue
            edges = osm_pbf.rounded((box.south, box.west, box.north, box.east), 5)
            requests.append(osm_pbf.Request(name=f"huts:{park_id}", huts=edges))
            if any(park["id"] == park_id for park in trailless):
                requests.append(osm_pbf.Request(
                    name=f"trails:{park_id}", trails=edges,
                    trail_kinds=abroad_trails.OSM_TRAIL_KINDS,
                ))
        if requests:
            wanted[code] = requests
    for code, requests in wanted.items():
        part_path = parts_dir / f"{code.lower()}.json"
        if _skip(part_path, refresh):
            continue
        _check_disk(f"{OSM} {code}")
        extract = osm_pbf.extract_for(f"ca-{code.lower()}")
        path = osm_pbf.latest(extract.source, extract.filename)
        if path is None:
            print(f"    {OSM}: downloading {extract.url}", flush=True)
            path = osm_pbf.download(
                rawstore.version_directory(extract.source, version),
                url=extract.url, filename=extract.filename,
            )
        print(f"    {OSM}: reading {len(requests)} selections out of {path.name}", flush=True)
        selected = osm_pbf.select(path, requests)
        described = osm_pbf.describe(path)
        part = {
            "province": code,
            "extract": described,
            "selections": {name: elements for name, elements in selected.items()},
        }
        part_path.write_text(json.dumps(part, ensure_ascii=False))
        path.unlink()
        print(f"    {OSM}: {code} read and its extract deleted "
              f"({free_bytes() / 1024**3:.1f} GB free)", flush=True)
    _combine_osm(directory, parts_dir, [park["id"] for park in trailless], version)


def _combine_osm(directory: Path, parts_dir: Path, trailless: list[str], version: str) -> None:
    """The per-province selections as the files the build reads: one rail file, one
    stations file, one huts file, and a trail file per park."""
    from ..abroad import trails as abroad_trails

    parts = [json.loads(path.read_text()) for path in sorted(parts_dir.glob("*.json"))]
    missing = sorted(set(osm_pbf.CANADA_PROVINCES) - {part["province"] for part in parts})
    if missing:
        print(f"    {OSM}: not yet read from {', '.join(missing)}; run again to resume")
        return
    record = FetchRecord(source=OSM_TERMS, fetched_at=rawstore.utc_now())
    stamps = sorted({(part["extract"] or {}).get("replicationTimestamp", "") for part in parts})
    header = {
        "version": 0.6,
        "generator": f"unigrids-pipeline {__version__} from Geofabrik's Canadian extracts",
        "osm3s": {"timestamp_osm_base": stamps[-1] if stamps else ""},
    }
    rail_parts = [part["selections"].get("rail") or [] for part in parts]
    routes = merge_routes([as_out_geom(elements) for elements in rail_parts])
    stations = _merge_elements([
        [e for e in elements if e.get("type") == "node" and e.get("tags")]
        for elements in rail_parts
    ])
    huts = _merge_elements([
        elements for part in parts for name, elements in part["selections"].items()
        if name.startswith("huts:")
    ])
    for name, elements in ((RAIL_FILE, routes), (STATIONS_FILE, stations), (HUTS_FILE, huts)):
        osm_pbf.write_elements(directory / name, elements, **header)
        record.add_file(directory / name, root=directory)
    for part in parts:
        record.add_request(part["extract"].get("url", ""), part["extract"])
    _write_record(record, directory)
    print(f"    {OSM}: {len(routes)} train routes, {len(stations)} station nodes, "
          f"{len(huts)} huts")
    for park in content.parks():
        if park["id"] not in trailless:
            continue
        elements = _merge_elements([
            part["selections"].get(f"trails:{park['id']}") or [] for part in parts
        ])
        abroad_trails.write_osm("ca", park, elements, version, abroad_trails.OSM_EXTRACT_TERMS,
                  "https://download.geofabrik.de/north-america/canada/",
                  {"extracts": [part["extract"].get("extract") for part in parts]})
        print(f"    {abroad_trails.OSM_TRAIL_SOURCES['ca']}/{park['id']}: {len(elements)} "
              "elements from the extracts", flush=True)


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
