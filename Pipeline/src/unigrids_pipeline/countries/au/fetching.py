"""Fetching Australia's sources into the date-versioned raw store.

Every source lands in ``raw/<date>/au-<source>/`` with a ``source.json`` beside it, and
every step resumes where an earlier run stopped: a file already in today's snapshot is left
alone unless ``refresh`` asks otherwise.

``au-capad/``
    The Collaborative Australian Protected Areas Database, CAPAD 2024 (DCCEEW, CC BY 4.0):
    every record of the 51 national parks with a guide, and every record CAPAD types
    "National Park", with their outlines in WGS84.
``au-states/``
    The ABS's states and territories (ASGS Edition 3, 2021; CC BY 4.0), to say which a
    place lies in.
``au-qpws-tracks/``
    Queensland Parks and Wildlife Service's walking tracks, with their AS 2156.1 class
    (CC BY 4.0).
``au-wikidata/``, ``au-wikipedia/``, ``au-commons/``, ``au-photos/``
    Australia's protected areas on Wikidata, English Wikipedia leads for the state
    national parks, Commons licence metadata for every photograph a guide or item names,
    and the guides' photographs themselves.
``au-documents/``
    Each national park's page on its agency's site, as its guide's sources give it, and
    the PDFs it links, each checked with HEAD.
``au-osm/``
    Passenger rail routes and stations, and the visitor centres, campgrounds and huts in
    and beside each national park, read out of Geofabrik's Australian extract (ODbL) with
    every park's trails (``au-osm-trails/``) in the same pass; the extract is deleted once
    read.
``au-climate/``
    Ten years of Open-Meteo daily weather at each park's centre (``climate``).

Requests identify the app and nothing else, and pause between calls.
"""

from __future__ import annotations

import html as html_lib
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
from ..no import rules as norway_rules
from . import content, qldtracks, rules, wiki

USER_AGENT = shared.USER_AGENT

# Raw store sources.
CAPAD = "au-capad"
STATES = "au-states"
TRACKS = qldtracks.SOURCE
WIKIDATA = "au-wikidata"
WIKIPEDIA = "au-wikipedia"
COMMONS = "au-commons"
PHOTOS = "au-photos"
DOCUMENTS = "au-documents"
OSM = "au-osm"
CLIMATE = "au-climate"

# MARK: - Endpoints and terms

CAPAD_LAYER = (
    "https://gis.environment.gov.au/gispubmap/rest/services/ogc_services/CAPAD/MapServer/0"
)
CAPAD_FIELDS = (
    "OBJECTID,PA_ID,PA_PID,NAME,TYPE,GAZ_AREA,GIS_AREA,GAZ_DATE,LATEST_GAZ,STATE,AUTHORITY,"
    "GOVERNANCE,ENVIRON,IUCN"
)
STATES_LAYER = "https://geo.abs.gov.au/arcgis/rest/services/ASGS2021/STE/MapServer/0"
QPWS_SERVICE = (
    "https://spatial-gis.information.qld.gov.au/arcgis/rest/services/Environment/"
    "ParksTerrestrialProtectedAreas/MapServer"
)
QPWS_TRACKS_LAYER = f"{QPWS_SERVICE}/5"
QPWS_FIELDS = "objectid,name,status,class,subcat,ped,mtb,horse,gw,owner"
EXPECTED_NATIONAL_PARKS = 51

CC_BY = "CC BY 4.0"
CAPAD_ATTRIBUTION = (
    "© Commonwealth of Australia (Department of Climate Change, Energy, the Environment and "
    "Water), Collaborative Australian Protected Areas Database (CAPAD) 2024, CC BY 4.0"
)

CAPAD_TERMS = SourceTerms(
    identifier="au-capad",
    title="Collaborative Australian Protected Areas Database (CAPAD) 2024: national parks",
    url=CAPAD_LAYER,
    licence=CC_BY,
    attribution=CAPAD_ATTRIBUTION,
    notes="Geometry in WGS84 (outSR 4326), generalised by the service to about 10 m for the "
    "parks with a guide and 50 m for the rest (maxAllowableOffset), then simplified by "
    "Unigrids before it ships. Data current at 30 June 2024. Dataset: "
    "https://fed.dcceew.gov.au/datasets/erin::collaborative-australian-protected-areas-"
    "database-capad-2024-terrestrial",
)
STATE_TERMS = SourceTerms(
    identifier="au-abs-ste",
    title="Australian Bureau of Statistics, ASGS Edition 3 (2021): States and Territories",
    url=STATES_LAYER,
    licence=CC_BY,
    attribution="Australian Bureau of Statistics, Australian Statistical Geography Standard "
    "(ASGS) Edition 3, CC BY 4.0",
    notes="Generalised by the service to about 100 m (maxAllowableOffset 0.001°); used only "
    "to say which state or territory a place lies in.",
)
TRACK_TERMS = SourceTerms(
    identifier="au-qpws-tracks",
    title="Queensland Parks and Wildlife Service access: walking tracks",
    url=QPWS_TRACKS_LAYER,
    licence=CC_BY,
    attribution="© State of Queensland (Department of the Environment, Tourism, Science and "
    "Innovation), CC BY 4.0",
    notes="The 'Walking track' layer of QSpatial's ParksTerrestrialProtectedAreas service, "
    "every record, in WGS84. The build keeps open, named records with a walking class. "
    "Open-data record: " + rules.QPWS_TRACKS_URL,
)
WIKIDATA_TERMS = SourceTerms(
    identifier="au-wikidata",
    title="Wikidata: Australia's protected areas and parks",
    url=shared.SPARQL,
    licence="CC0",
    attribution="Wikidata",
    notes="Used for each place's English Wikipedia article, P18 image and Commons category.",
)
WIKIPEDIA_TERMS = SourceTerms(
    identifier="au-wikipedia",
    title="English Wikipedia leads (Action API, intro extracts) for Australia's state "
    "national parks",
    url=shared.WIKIPEDIA_API,
    licence="CC BY-SA 4.0",
    attribution="Summaries: Wikipedia, CC BY-SA 4.0, linked from each place",
)
COMMONS_TERMS = SourceTerms(
    identifier="au-commons",
    title="Wikimedia Commons licence and author metadata",
    url=shared.COMMONS_API,
    licence="Per file",
    attribution="Photographs credited individually, via Wikimedia Commons",
    notes="Every photograph keeps its credit and licence, and is marked public domain only "
    "when its licence says so. No agency's own photographs or logos are used.",
)
PHOTO_TERMS = SourceTerms(
    identifier="au-photos",
    title="Wikimedia Commons photographs named in Australia's guides",
    url=shared.COMMONS_FILE_PATH,
    licence="Per file (see au-commons/licences.json)",
    attribution="Photographs credited individually, via Wikimedia Commons",
    notes=f"Downloaded at {shared.PHOTO_WIDTH} px wide and resized by the build.",
)
DOCUMENT_TERMS = SourceTerms(
    identifier="au-documents",
    title="The national parks' pages on Parks Australia's and the state agencies' sites, and "
    "the PDFs they link",
    url="https://parksaustralia.gov.au/",
    licence="Crown copyright; links only, nothing is extracted",
    attribution="Parks Australia and the state and territory park agencies",
    notes="Each page read as HTML; every PDF checked with HEAD.",
)
OSM_TERMS = SourceTerms(
    identifier="openstreetmap-au",
    title="OpenStreetMap from Geofabrik's Australian extract: passenger rail, stations, "
    "visitor centres, campgrounds and huts",
    url="https://www.openstreetmap.org/copyright",
    licence="Open Database License (ODbL) 1.0",
    attribution="© OpenStreetMap contributors",
    notes="route=train relations with their member ways and stops, railway stations, and "
    "tourism=camp_site|alpine_hut|wilderness_hut and tourism=information + "
    "information=office in and beside each national park, read out of Geofabrik's "
    "australia .osm.pbf and written in Overpass's shapes. Shipped as data: a Derivative "
    "Database under the ODbL.",
)

# South, west, north, east: the mainland and Tasmania. The island territories have no
# railway.
RAIL_BOX = (-43.7, 112.9, -10.6, 153.7)
RAIL_FILE = "rail-routes-au.json"
STATIONS_FILE = "stations.json"
FACILITIES_FILE = "facilities.json"
# How far beyond a park's outline its facilities are looked for: visitor centres stand in
# the towns at a park's edge (Jindabyne, Katoomba, Jabiru).
FACILITY_REACH_KM = 15.0
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
    """Fetch everything Australia's ``assemble`` reads into ``raw/<today>/``. Returns the
    version directory."""
    version = rawstore.today()
    root = rawstore.version_directory(CAPAD, version).parent
    with client() as session:
        _fetch_capad(session, version, refresh=refresh)
        areas = read_areas(root / CAPAD)
        _fetch_states(session, version, refresh=refresh)
        _fetch_tracks(session, version, refresh=refresh)
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
    # Trails: QPWS's for Queensland's parks, OpenStreetMap's (already read out of the
    # extract) for every park; then the elevation tiles the kept routes cross, and each
    # park's range, kept so the tiles can go.
    from ..abroad import elevation as abroad_elevation
    from ..abroad import trails as abroad_trails

    _check_disk("trails")
    abroad_trails.fetch("au", list(content.parks()), outlines, refresh=False)
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


# MARK: - CAPAD


def _quoted(values: list[str]) -> str:
    return ",".join("'" + value.replace("'", "''") + "'" for value in values)


def flagship_where() -> str:
    names = sorted({name for park in content.parks() for name in content.capad_names(park)})
    return f"NAME IN ({_quoted(names)}) AND TYPE IN ({_quoted(sorted(rules.NATIONAL_PARK_TYPES))})"


def second_tier_where() -> str:
    return f"TYPE = '{rules.SECOND_TIER_TYPE}'"


def _fetch_capad(session: httpx.Client, version: str, *, refresh: bool) -> None:
    directory = rawstore.version_directory(CAPAD, version)
    record = FetchRecord(source=CAPAD_TERMS, fetched_at=rawstore.utc_now())
    queries = {
        "national-parks.geojson": (flagship_where(), "0.0001", 10),
        "state-national-parks.geojson": (second_tier_where(), "0.0005", 50),
    }
    for name, (where, offset, page) in queries.items():
        path = directory / name
        if _skip(path, refresh):
            print(f"    {CAPAD}/{name}: already fetched today")
            continue
        features = arcgis_query(
            session, CAPAD_LAYER,
            {"where": where, "outFields": CAPAD_FIELDS, "orderByFields": "OBJECTID",
             "maxAllowableOffset": offset},
            record=record, page_size=page,
        )
        path.write_text(_collection(features))
        record.add_file(path, root=directory)
        print(f"    {CAPAD}/{name}: {len(features)} records")
    _write_record(record, directory)


class Area:
    """One park's CAPAD records as fetched — every record of its name and state — with
    their properties and outline."""

    def __init__(self, name: str, state: str, tier: str) -> None:
        self.capad_name = name
        self.state = state
        """CAPAD's ``STATE``: ``NSW`` … ``JBT``, or ``EXT`` for an island territory."""
        self.tier = tier
        self.polygons: list[outline.Polygon] = []
        self.parts: list[dict[str, Any]] = []
        self._centre: tuple[float, float] | None = None
        self._centre_known = False

    @property
    def key(self) -> str:
        """``NSW/Blue Mountains``: how CAPAD tells one park from another."""
        return f"{self.state}/{self.capad_name}"

    def add(self, feature: dict[str, Any]) -> None:
        self.polygons.extend(outline.polygons_of(feature.get("geometry")))
        self.parts.append(feature.get("properties") or {})
        self._centre_known = False

    def merge(self, other: Area) -> None:
        self.polygons.extend(other.polygons)
        self.parts.extend(other.parts)
        self._centre_known = False

    @property
    def name(self) -> str | None:
        return rules.display_name(self.capad_name)

    @property
    def authority(self) -> str | None:
        authorities = [part.get("AUTHORITY") for part in self.parts if part.get("AUTHORITY")]
        return max(set(authorities), key=authorities.count) if authorities else None

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
    """``<tier>:<STATE>/<NAME>`` → the park's records: ``np`` for the parks with a guide
    (every record under their CAPAD names, in their own state), ``snp`` for every other
    park CAPAD types "National Park". A park's parcels are one park."""
    areas: dict[str, Area] = {}
    if directory is None:
        return areas
    flagships: dict[tuple[str, str], str] = {}
    for park in content.parks():
        state = rules.capad_state_of(park["state"])
        for name in content.capad_names(park):
            flagships[(state, name)] = park["id"]
    for filename in ("national-parks.geojson", "state-national-parks.geojson"):
        path = directory / filename
        if not path.exists():
            continue
        for feature in json.loads(path.read_text()).get("features") or []:
            properties = feature.get("properties") or {}
            name = re.sub(r"\s+", " ", properties.get("NAME") or "").strip()
            state = (properties.get("STATE") or "").strip().upper()
            kind = properties.get("TYPE")
            if not name or not state:
                continue
            park_id = flagships.get((state, name))
            if park_id is not None and kind in rules.NATIONAL_PARK_TYPES:
                key = f"np:{park_id}"
                area = areas.setdefault(key, Area(name, state, "np"))
            elif park_id is None and kind == rules.SECOND_TIER_TYPE:
                key = f"snp:{state}/{name}"
                area = areas.setdefault(key, Area(name, state, "snp"))
            else:
                continue
            # A record fetched by both queries is one record.
            if any(part.get("OBJECTID") == properties.get("OBJECTID") for part in area.parts):
                continue
            area.add(feature)
    return areas


def national_parks(areas: dict[str, Area]) -> list[tuple[dict[str, Any], Area | None]]:
    """Each park in the content list with its CAPAD records."""
    return [(park, areas.get(f"np:{park['id']}")) for park in content.parks()]


def second_tier(areas: dict[str, Area]) -> list[Area]:
    """Every other national park, in state and name order so identifiers are minted the
    same way every run."""
    return sorted(
        (area for area in areas.values() if area.tier == "snp"),
        key=lambda area: (area.state, area.capad_name),
    )


# MARK: - States and territories


def _fetch_states(session: httpx.Client, version: str, *, refresh: bool) -> None:
    directory = rawstore.version_directory(STATES, version)
    path = directory / "states.geojson"
    if _skip(path, refresh):
        print(f"    {STATES}: already fetched today")
        return
    record = FetchRecord(source=STATE_TERMS, fetched_at=rawstore.utc_now())
    features = arcgis_query(
        session, STATES_LAYER,
        {"where": "1=1", "outFields": "state_code_2021,state_name_2021",
         "maxAllowableOffset": "0.001", "orderByFields": "state_code_2021"},
        record=record, page_size=2,
    )
    path.write_text(_collection(features))
    record.add_file(path, root=directory)
    _write_record(record, directory)
    print(f"    {STATES}: {len(features)} states and territories")


def read_states(path: Path) -> dict[str, list[outline.Polygon]]:
    """The app's state code → its polygons. The ABS's Other Territories are split by
    where each polygon lies: Jervis Bay, Christmas Island, Cocos and Norfolk Island."""
    states: dict[str, list[outline.Polygon]] = {}
    for feature in json.loads(path.read_text()).get("features") or []:
        properties = feature.get("properties") or {}
        for polygon in outline.polygons_of(feature.get("geometry")):
            if not polygon or not polygon[0]:
                continue
            longitude, latitude = polygon[0][0]
            code = rules.abs_state(properties.get("state_code_2021"), latitude, longitude)
            if code:
                states.setdefault(code, []).append(polygon)
    return states


def states_index(directory: Path | None) -> norway_rules.Counties | None:
    """Point-in-polygon over the states, as Norway's counties are tested."""
    if directory is None or not (directory / "states.geojson").exists():
        return None
    return norway_rules.Counties(read_states(directory / "states.geojson"))


# MARK: - Queensland's tracks


def _fetch_tracks(session: httpx.Client, version: str, *, refresh: bool) -> None:
    directory = rawstore.version_directory(TRACKS, version)
    path = directory / qldtracks.FILE
    if _skip(path, refresh):
        print(f"    {TRACKS}: already fetched today")
        return
    record = FetchRecord(source=TRACK_TERMS, fetched_at=rawstore.utc_now())
    features = arcgis_query(
        session, QPWS_TRACKS_LAYER,
        {"where": "1=1", "outFields": QPWS_FIELDS, "orderByFields": "objectid"},
        record=record, page_size=1000,
    )
    path.write_text(_collection(features))
    record.add_file(path, root=directory)
    _write_record(record, directory)
    print(f"    {TRACKS}: {len(features)} records")


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


def wiki_matches(
    areas: dict[str, Area], others: list[dict[str, Any]]
) -> dict[str, dict[str, Any]]:
    """``snp:<STATE>/<NAME>`` (or ``np:<id>``) → the Wikidata item that is the place's
    own, the parks with a guide matched with the rest so a park's item is never a
    neighbour's."""
    places = [
        (f"np:{park['id']}", "np", area.capad_name, area.centre, area.reach_km)
        for park, area in national_parks(areas) if area is not None
    ]
    places.extend(
        (f"snp:{area.key}", "snp", area.name or area.capad_name, area.centre, area.reach_km)
        for area in second_tier(areas)
    )
    return wiki.own_matches(places, others)


def second_tier_matches(
    wikidata_dir: Path, areas: dict[str, Area]
) -> dict[str, dict[str, Any]]:
    found = wiki_matches(areas, read_candidates(wikidata_dir))
    chosen = second_tier(areas)
    matches = {
        f"snp:{area.key}": found[f"snp:{area.key}"]
        for area in chosen if f"snp:{area.key}" in found
    }
    with_article = sum(1 for item in matches.values() if item.get("article"))
    print(
        f"    {WIKIDATA}: {len(matches)} of {len(chosen)} state national parks matched, "
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
    """Licence and author for every photograph a guide names and every state national
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
    """Every PDF an agency's park page links, absolute, once each, with the link's text as
    its title where the page gives one ("Park map (PDF 1.2MB)" → "Park map")."""
    found: list[dict[str, str]] = []
    seen: set[str] = set()
    for href, text in _ANCHOR.findall(html):
        url = urljoin(page_url, html_lib.unescape(href.strip()))
        if url in seen:
            continue
        seen.add(url)
        label = re.sub(r"\s+", " ", html_lib.unescape(re.sub(r"<[^>]+>", " ", text))).strip()
        label = re.sub(r"\s*[\(\[]\s*PDF\b[^)\]]*[\)\]]?\s*$", "", label, flags=re.IGNORECASE)
        found.append({"title": label.strip(), "url": url})
    return found


def official_page(park: dict[str, Any]) -> str | None:
    return rules.official_page((content.guide(park["id"]) or {}).get("sources"))


def _fetch_documents(session: httpx.Client, version: str, *, refresh: bool) -> None:
    directory = rawstore.version_directory(DOCUMENTS, version)
    pages_dir = directory / "pages"
    pages_dir.mkdir(exist_ok=True)
    record = FetchRecord(source=DOCUMENT_TERMS, fetched_at=rawstore.utc_now())
    heads_path = directory / "heads.json"
    heads: dict[str, Any] = _load(heads_path, refresh)
    links: dict[str, Any] = {}
    for park in content.parks():
        url = official_page(park)
        if not url:
            print(f"    {DOCUMENTS}: {park['id']} names no agency page")
            continue
        path = pages_dir / f"{park['id']}.html"
        if _skip(path, refresh):
            html = path.read_text()
        else:
            try:
                response = http.get(session, url, expect="text/html")
            except http.FetchError as error:
                print(f"    {DOCUMENTS}: {park['id']} page failed ({error})")
                links[park["id"]] = {"page": url, "documents": []}
                continue
            html = response.text
            path.write_text(html)
            record.add_request(url)
            record.add_file(path, root=directory)
            time.sleep(http.DEFAULT_POLITENESS.pause_seconds)
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
    heads_path.write_text(json.dumps(heads, ensure_ascii=False, indent=1))
    links_path = directory / "links.json"
    links_path.write_text(json.dumps(links, ensure_ascii=False, indent=1))
    record.add_file(links_path, root=directory)
    _write_record(record, directory)
    documents = sum(len(entry["documents"]) for entry in links.values())
    print(f"    {DOCUMENTS}: {len(links)} park pages, {documents} PDFs that answer")


# MARK: - OpenStreetMap


def facility_box(polygons: list[outline.Polygon]) -> tuple[float, float, float, float] | None:
    """The park's box with :data:`FACILITY_REACH_KM` around it, as an extract read takes
    it (south, west, north, east)."""
    found = outline.bbox(polygons)
    if found is None:
        return None
    south, west, north, east = found
    box = geo.BoundingBox(west=west, south=south, east=east, north=north).buffered(
        FACILITY_REACH_KM * 1000
    )
    return osm_pbf.rounded((box.south, box.west, box.north, box.east), 5)


def _fetch_osm(
    version: str, outlines: dict[str, list[outline.Polygon]], *, refresh: bool
) -> None:
    """Rail and stations, each park's visitor centres, campgrounds and huts, and every
    park's trails, read out of Geofabrik's Australian extract in one pass. The extract is
    downloaded only while one of those files is missing, and deleted once read."""
    from ..abroad import trails as abroad_trails

    directory = rawstore.version_directory(OSM, version)
    rail_path = directory / RAIL_FILE
    stations_path = directory / STATIONS_FILE
    facilities_path = directory / FACILITIES_FILE
    want_layers = refresh or any(
        rawstore.latest(OSM, name) is None for name in (RAIL_FILE, FACILITIES_FILE)
    )
    trail_source = abroad_trails.OSM_TRAIL_SOURCES["au"]
    trailless = [
        (park, outlines[park["id"]])
        for park in content.parks()
        if park["id"] in outlines
        and (refresh or rawstore.latest(trail_source, f"{park['id']}.json") is None)
    ]
    if not want_layers and not trailless:
        print(f"    {OSM}: rail, facilities and trails already read from an extract")
        return
    _check_disk(OSM)
    extract = osm_pbf.extract_for("au")
    path = None if refresh else osm_pbf.latest(extract.source, extract.filename)
    if path is None:
        print(f"    {OSM}: downloading {extract.url}", flush=True)
        path = osm_pbf.download(
            rawstore.version_directory(extract.source, version),
            url=extract.url, filename=extract.filename, refresh=refresh,
        )
    requests: list[osm_pbf.Request] = []
    if want_layers:
        requests.append(osm_pbf.Request(name="rail", rail=RAIL_BOX, stations=RAIL_BOX))
        for park_id, polygons in outlines.items():
            if (box := facility_box(polygons)) is not None:
                requests.append(osm_pbf.Request(name=f"facilities:{park_id}", facilities=box))
    for park, polygons in trailless:
        if (request := abroad_trails.extract_request(park, polygons)) is not None:
            request.name = f"trails:{park['id']}"
            requests.append(request)
    print(f"    {OSM}: reading {len(requests)} selections out of {path.name}", flush=True)
    selected = osm_pbf.select(path, requests)
    described = osm_pbf.describe(path)
    if want_layers:
        header = {
            "version": 0.6,
            "generator": f"unigrids-pipeline {__version__} from {path.name}",
            "osm3s": {"timestamp_osm_base": described.get("replicationTimestamp", "")},
        }
        elements = selected["rail"]
        routes = as_out_geom(elements)
        stations = [e for e in elements if e.get("type") == "node" and e.get("tags")]
        facilities: dict[tuple[str, int], dict[str, Any]] = {}
        for name, found in selected.items():
            if name.startswith("facilities:"):
                for element in found:
                    facilities.setdefault((element["type"], element["id"]), element)
        record = FetchRecord(source=OSM_TERMS, fetched_at=rawstore.utc_now())
        osm_pbf.write_elements(rail_path, routes, **header)
        osm_pbf.write_elements(stations_path, stations, **header)
        osm_pbf.write_elements(
            facilities_path, [facilities[key] for key in sorted(facilities)], **header
        )
        record.add_request(described["url"], {**described, "rail": RAIL_BOX},
                           elements=len(elements))
        for written in (rail_path, stations_path, facilities_path):
            record.add_file(written, root=directory)
        _write_record(record, directory)
        print(f"    {OSM}: {len(routes)} train routes, {len(stations)} station nodes, "
              f"{len(facilities)} visitor centres, campgrounds and huts")
    if trailless:
        abroad_trails.fetch_osm_extract(
            "au", trailless, version, path,
            selected={
                park["id"]: selected[f"trails:{park['id']}"] for park, _ in trailless
                if f"trails:{park['id']}" in selected
            },
        )
    path.unlink()
    print(f"    {OSM}: extract read and deleted ({free_bytes() / 1024**3:.1f} GB free)",
          flush=True)


def as_out_geom(elements: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Train route relations from an extract read, in Overpass's ``out geom`` shape."""
    from ..nz import fetching as new_zealand

    return new_zealand.as_out_geom(elements)


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
