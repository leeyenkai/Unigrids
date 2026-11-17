"""Fetching Norway's sources into the date-versioned raw store.

Every source lands in ``raw/<date>/no-<source>/`` with a ``source.json`` beside it — the
``no-`` prefix keeps Norway's files apart from the US's and Japan's on the same date —
and every step resumes where an earlier run stopped: a file already in today's snapshot
is left alone unless ``refresh`` asks otherwise.

``no-naturvern/``
    Miljødirektoratet's Naturvernområder: the 48 national parks, the 195 landscape
    protection areas and every nature reserve of 5 km² or more, with their official
    geometry in WGS84 (NLOD 2.0).
``no-restrictions/``
    The seasonal and standing restriction zones (traffic, landing and low-flying bans)
    inside each national park's extent.
``no-counties/``
    Kartverket's fifteen counties (CC BY 4.0), as published.
``no-wikidata/``, ``no-wikipedia/``, ``no-commons/``, ``no-photos/``
    Each place's Wikidata item, English Wikipedia leads for the protected landscapes and
    reserves, Commons licence metadata for every photograph a guide or item names, and
    the guides' photographs themselves.
``no-documents/``
    Each national park's page on norgesnasjonalparker.no and the PDFs it links, each
    checked with a HEAD request.
``no-osm/``
    OpenStreetMap through Overpass, region by region: huts, railway stations with their
    stop areas, and passenger rail routes (ODbL).
``no-climate/``
    Ten years of Open-Meteo daily weather at each park's centre (``climate``).

Requests identify the app and nothing else — no person, no repository owner — and pause
between calls: these are government services and volunteer-run infrastructure.
"""

from __future__ import annotations

import io
import json
import re
import time
import zipfile
from pathlib import Path
from typing import Any
from urllib.parse import quote, urljoin

import httpx

from ... import __version__, climate, config, geo, outline, rawstore
from ...rawstore import FetchRecord, SourceTerms
from ...sources import http, osm
from ..common import photo_filename
from . import content, rules, wiki

USER_AGENT = (
    f"UnigridsPipeline/{__version__} (offline reference-data builder for the Unigrids app) "
    f"python-httpx/{httpx.__version__}"
)

# Raw store sources.
NATURVERN = "no-naturvern"
RESTRICTIONS = "no-restrictions"
COUNTIES = "no-counties"
WIKIDATA = "no-wikidata"
WIKIPEDIA = "no-wikipedia"
COMMONS = "no-commons"
PHOTOS = "no-photos"
DOCUMENTS = "no-documents"
OSM = "no-osm"
CLIMATE = "no-climate"

# MARK: - Endpoints and terms

VERN_LAYER = "https://kart.miljodirektoratet.no/arcgis/rest/services/vern/MapServer/0"
VERN_FIELDS = (
    "naturvernId,navn,offisieltNavn,verneform,vernedato,foerstegangVernet,kommune,"
    "forvaltningsmyndighet,faktaark,iucn,SHAPE.STArea()"
)
# File → which features. Landscape areas come in combined forms and reserves in Svalbard's
# and Jan Mayen's, so both are selected by prefix.
VERN_QUERIES = {
    "national-parks.geojson": "verneform IN ('Nasjonalpark','NasjonalparkSvalbard')",
    "landscapes.geojson": "verneform LIKE 'Landskapsvernomraade%'",
    "reserves.geojson": (
        "verneform LIKE 'Naturreservat%' "
        f"AND SHAPE.STArea() >= {rules.RESERVE_FETCH_MINIMUM_M2}"
    ),
}
VERN_COUNTS = {
    "nationalParks": "verneform IN ('Nasjonalpark','NasjonalparkSvalbard')",
    "landscapes": "verneform LIKE 'Landskapsvernomraade%'",
    "reserves": "verneform LIKE 'Naturreservat%'",
}
EXPECTED = {"national-parks.geojson": 48, "landscapes.geojson": 195}

RESTRICTION_SERVICE = (
    "https://kart.miljodirektoratet.no/arcgis/rest/services/vern_restriksjonsomrader/MapServer"
)
RESTRICTION_LAYERS = {
    0: "ferdselsforbud",
    1: "lavflyving_forbudt_under_300m",
    2: "landingsforbud",
    3: "lavflyving_forbudt_under_300m_forsvaret",
    4: "landingsforbud_forsvaret",
}

COUNTIES_URL = (
    "https://nedlasting.geonorge.no/geonorge/Basisdata/Fylker/GeoJSON/"
    "Basisdata_0000_Norge_4258_Fylker_GeoJSON.zip"
)
COUNTIES_FILE = "fylker.zip"

SPARQL = "https://query.wikidata.org/sparql"
NATURBASE_QUERY = """SELECT ?item ?id ?article ?image ?commons ?coord WHERE {
  ?item wdt:P1732 ?id .
  OPTIONAL { ?article schema:about ?item ; schema:isPartOf <https://en.wikipedia.org/> . }
  OPTIONAL { ?item wdt:P18 ?image }
  OPTIONAL { ?item wdt:P373 ?commons }
  OPTIONAL { ?item wdt:P625 ?coord }
}"""
# Protected areas in Norway that carry no Naturbase ID, for matching by name and location.
CANDIDATE_QUERY = """SELECT ?item ?label ?article ?image ?commons ?coord WHERE {
  ?item wdt:P17 wd:Q20 ; wdt:P625 ?coord ; wdt:P31/wdt:P279* wd:Q473972 .
  FILTER NOT EXISTS { ?item wdt:P1732 [] }
  ?item rdfs:label ?label . FILTER(LANG(?label) IN ("nb", "nn", "en", "se"))
  OPTIONAL { ?article schema:about ?item ; schema:isPartOf <https://en.wikipedia.org/> . }
  OPTIONAL { ?item wdt:P18 ?image }
  OPTIONAL { ?item wdt:P373 ?commons }
}"""

WIKIPEDIA_API = "https://en.wikipedia.org/w/api.php"
COMMONS_API = "https://commons.wikimedia.org/w/api.php"
COMMONS_FILE_PATH = "https://commons.wikimedia.org/wiki/Special:FilePath/"
# Commons serves thumbnails at standard widths; 1920 is the one above the hero's 1600.
PHOTO_WIDTH = 1920

PORTAL = "https://www.norgesnasjonalparker.no"
PORTAL_LIST = f"{PORTAL}/nasjonalparker/"
SVALBARD_CARD = "nasjonalparkene på svalbard"

NATURVERN_TERMS = SourceTerms(
    identifier="no-naturvern",
    title="Naturvernområder (Miljødirektoratet): national parks, landscape protection areas "
    "and nature reserves",
    url=VERN_LAYER,
    licence="Norwegian Licence for Open Government Data (NLOD) 2.0",
    attribution="Contains data under the Norwegian licence for Open Government data (NLOD) "
    "distributed by Miljødirektoratet",
    notes="Geometry in WGS84 (outSR 4326). Reserves of 5 km² or more only. Outlines are "
    "simplified by Unigrids before they ship.",
)
RESTRICTION_TERMS = SourceTerms(
    identifier="no-restrictions",
    title="Restriksjonsområder naturvern (Miljødirektoratet): traffic, landing and "
    "low-flying bans",
    url=RESTRICTION_SERVICE,
    licence="Norwegian Licence for Open Government Data (NLOD) 2.0",
    attribution="Contains data under the Norwegian licence for Open Government data (NLOD) "
    "distributed by Miljødirektoratet",
    notes="Every zone in layers 0–4 whose extent meets a national park's extent; "
    "the build keeps those inside the park.",
)
COUNTY_TERMS = SourceTerms(
    identifier="no-counties",
    title="Administrative enheter fylker (Kartverket), GeoJSON, EPSG:4258",
    url=COUNTIES_URL,
    licence="CC BY 4.0",
    attribution="©Kartverket",
    notes="Fifteen counties from 1 January 2024; Svalbard is not among them.",
)
WIKIDATA_TERMS = SourceTerms(
    identifier="no-wikidata",
    title="Wikidata: items with a Naturbase ID (P1732), and Norwegian protected areas without",
    url=SPARQL,
    licence="CC0",
    attribution="Wikidata",
    notes="Used for each place's English Wikipedia article, P18 image and Commons category.",
)
WIKIPEDIA_TERMS = SourceTerms(
    identifier="no-wikipedia",
    title="English Wikipedia leads (Action API, intro extracts) for Norway's protected "
    "landscapes and reserves",
    url=WIKIPEDIA_API,
    licence="CC BY-SA 4.0",
    attribution="Summaries: Wikipedia, CC BY-SA 4.0, linked from each place",
)
COMMONS_TERMS = SourceTerms(
    identifier="no-commons",
    title="Wikimedia Commons licence and author metadata",
    url=COMMONS_API,
    licence="Per file",
    attribution="Photographs credited individually, via Wikimedia Commons",
    notes="Every photograph keeps its credit and licence, and is marked public domain only "
    "when its licence says so.",
)
PHOTO_TERMS = SourceTerms(
    identifier="no-photos",
    title="Wikimedia Commons photographs named in Norway's guides",
    url=COMMONS_FILE_PATH,
    licence="Per file (see no-commons/licences.json)",
    attribution="Photographs credited individually, via Wikimedia Commons",
    notes=f"Downloaded at {PHOTO_WIDTH} px wide and resized by the build.",
)
DOCUMENT_TERMS = SourceTerms(
    identifier="no-documents",
    title="Norges nasjonalparker park pages and the PDFs they link",
    url=PORTAL,
    licence="None stated; links only, nothing is extracted",
    attribution="Norges nasjonalparker (Miljødirektoratet)",
    notes="Each page read as JSON (the site's own content API); every PDF checked with HEAD.",
)
OSM_TERMS = SourceTerms(**{
    **osm.TERMS,
    "identifier": "no-openstreetmap",
    "notes": "Huts, railway stations and passenger rail routes, asked for by region; the "
    "build keeps huts inside a national park and stations within 100 km of one. Shipped as "
    "data, so the dataset owes the ODbL's attribution and share-alike for these layers.",
})


def client(politeness: http.Politeness = http.DEFAULT_POLITENESS) -> httpx.Client:
    """An HTTP client that names the app and no person."""
    return httpx.Client(
        headers={"User-Agent": USER_AGENT},
        timeout=politeness.timeout_seconds,
        follow_redirects=True,
    )


# MARK: - Fetch


def fetch(*, refresh: bool = False) -> Path:
    """Fetch everything Norway's ``assemble`` reads into ``raw/<today>/``. Returns the
    version directory."""
    version = rawstore.today()
    root = config.RAW_DIR / version
    with client() as session:
        _fetch_naturvern(session, version, refresh=refresh)
        _fetch_counties(session, version, refresh=refresh)
        areas = read_areas(root / NATURVERN)
        _fetch_restrictions(session, version, areas, refresh=refresh)
        _fetch_wikidata(session, version, refresh=refresh)
        matches = _second_tier_matches(root / WIKIDATA, areas)
        _fetch_wikipedia(session, version, matches, refresh=refresh)
        _fetch_commons(session, version, matches, refresh=refresh)
        _fetch_photos(session, version, refresh=refresh)
        _fetch_documents(session, version, areas, refresh=refresh)
        _fetch_climate(session, version, areas, refresh=refresh)
        # Last, because the public Overpass servers are the likeliest to turn work away.
        _fetch_osm(session, version, refresh=refresh)
    # Trails: Turrutebasen for every park, then OpenStreetMap for those it leaves empty.
    from ..abroad import outlines as abroad_outlines
    from ..abroad import trails as abroad_trails

    abroad_trails.fetch(
        "no", list(abroad_outlines.park_list("no")), abroad_outlines.outlines("no"),
        refresh=refresh,
    )
    return root


def _write_record(record: FetchRecord, directory: Path) -> None:
    """``source.json``, keeping the requests and files of an earlier partial fetch made the
    same day, so a resumed fetch still records everything it holds."""
    path = directory / "source.json"
    if path.exists():
        earlier = json.loads(path.read_text())
        refetched = {entry["path"] for entry in record.files}
        record.requests = [*earlier.get("requests", []), *record.requests]
        record.files = [
            *(entry for entry in earlier.get("files", []) if entry["path"] not in refetched),
            *record.files,
        ]
    record.write(directory)


def _skip(path: Path, refresh: bool) -> bool:
    return path.exists() and not refresh


# MARK: - Naturvernområder


def _fetch_naturvern(session: httpx.Client, version: str, *, refresh: bool) -> None:
    directory = rawstore.version_directory(NATURVERN, version)
    record = FetchRecord(source=NATURVERN_TERMS, fetched_at=rawstore.utc_now())
    for name, where in VERN_QUERIES.items():
        path = directory / name
        if _skip(path, refresh):
            print(f"    {NATURVERN}/{name}: already fetched today")
            continue
        features = arcgis_query(
            session,
            VERN_LAYER,
            {"where": where, "outFields": VERN_FIELDS, "orderByFields": "OBJECTID"},
            record=record,
            page_size=25 if name == "national-parks.geojson" else 50,
        )
        unique = {(f.get("properties") or {}).get("naturvernId") for f in features}
        path.write_text(json.dumps({"type": "FeatureCollection", "features": features}))
        record.add_file(path, root=directory)
        expected = EXPECTED.get(name)
        note = f" (expected {expected})" if expected and expected != len(unique) else ""
        print(f"    {NATURVERN}/{name}: {len(features)} features, {len(unique)} areas{note}")
    counts_path = directory / "counts.json"
    if not _skip(counts_path, refresh):
        counts = {}
        for key, where in VERN_COUNTS.items():
            response = http.get(
                session, f"{VERN_LAYER}/query",
                params={"where": where, "returnCountOnly": "true", "f": "json"},
                expect="application",
            )
            counts[key] = response.json().get("count")
            record.add_request(f"{VERN_LAYER}/query", {"where": where, "returnCountOnly": True})
        counts_path.write_text(json.dumps(counts, indent=1) + "\n")
        record.add_file(counts_path, root=directory)
        print(f"    {NATURVERN}: in the whole dataset {counts}")
    _write_record(record, directory)


def arcgis_query(
    session: httpx.Client,
    layer: str,
    parameters: dict[str, str],
    *,
    record: FetchRecord | None = None,
    page_size: int = 100,
) -> list[dict[str, Any]]:
    """Every feature an ArcGIS layer returns for ``parameters``, as GeoJSON in WGS84,
    paging until the server stops holding back. A refusal is retried twice before it is
    believed: a busy service sometimes answers a valid page with an error."""
    features: list[dict[str, Any]] = []
    offset = 0
    while True:
        query = {
            "returnGeometry": "true",
            "outSR": "4326",
            "geometryPrecision": "6",
            "f": "geojson",
            **parameters,
            "resultOffset": str(offset),
            "resultRecordCount": str(page_size),
        }
        payload: dict[str, Any] = {}
        for attempt in range(3):
            response = http.get(session, f"{layer}/query", params=query, expect="application")
            payload = response.json()
            if "error" not in payload:
                break
            time.sleep(5 * (attempt + 1))
        else:
            raise http.FetchError(f"{layer} refused the query: {payload.get('error')}")
        if record is not None:
            record.add_request(f"{layer}/query", query)
        page = payload.get("features") or []
        features.extend(page)
        exceeded = payload.get("exceededTransferLimit") or (
            payload.get("properties") or {}
        ).get("exceededTransferLimit")
        if not page or not exceeded:
            return features
        offset += len(page)


class Area:
    """One protected area as fetched: its properties, outline and where to look for it."""

    def __init__(self, feature: dict[str, Any], tier: str) -> None:
        self.properties: dict[str, Any] = feature.get("properties") or {}
        self.tier = tier
        self.polygons: list[outline.Polygon] = outline.polygons_of(feature.get("geometry"))

    @property
    def naturvern_id(self) -> str:
        return self.properties.get("naturvernId") or ""

    @property
    def name(self) -> str:
        return rules.strip_designation(self.properties.get("navn") or "")

    @property
    def area_m2(self) -> float:
        return rules.area_m2(self.properties)

    def merge(self, other: Area) -> None:
        """A second feature for the same area: one more piece of its outline."""
        self.polygons.extend(other.polygons)

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


def read_areas(directory: Path) -> dict[str, Area]:
    """``naturvernId`` → the area, for every national park, landscape area and reserve
    fetched. A park the service splits into several features is joined into one."""
    areas: dict[str, Area] = {}
    for name in VERN_QUERIES:
        path = directory / name
        if not path.exists():
            continue
        for feature in json.loads(path.read_text()).get("features") or []:
            tier = rules.tier_of((feature.get("properties") or {}).get("verneform"))
            if tier is None:
                continue
            area = Area(feature, tier)
            if not area.naturvern_id:
                continue
            if area.naturvern_id in areas:
                areas[area.naturvern_id].merge(area)
            else:
                areas[area.naturvern_id] = area
    return areas


def national_parks(areas: dict[str, Area]) -> list[tuple[dict[str, Any], Area | None]]:
    """Each park in the content list with its Naturvernområder record, in list order."""
    return [(park, areas.get(park["naturvernId"])) for park in content.parks()]


def second_tier(areas: dict[str, Area]) -> list[Area]:
    """Every landscape protection area, and every nature reserve of 10 km² or more, in
    ``naturvernId`` order so identifiers are minted the same way every run."""
    chosen = [
        area
        for area in areas.values()
        if area.tier == "lvo" or (area.tier == "nr" and rules.carries_reserve(area.properties))
    ]
    return sorted(chosen, key=lambda area: area.naturvern_id)


# MARK: - Restrictions


def _fetch_restrictions(
    session: httpx.Client, version: str, areas: dict[str, Area], *, refresh: bool
) -> None:
    directory = rawstore.version_directory(RESTRICTIONS, version)
    parks_dir = directory / "parks"
    parks_dir.mkdir(exist_ok=True)
    record = FetchRecord(source=RESTRICTION_TERMS, fetched_at=rawstore.utc_now())
    fetched = 0
    for park, area in national_parks(areas):
        path = parks_dir / f"{park['id']}.json"
        if _skip(path, refresh) or area is None or area.box is None:
            continue
        box = area.box
        found: list[dict[str, Any]] = []
        for layer, kind in RESTRICTION_LAYERS.items():
            features = arcgis_query(
                session,
                f"{RESTRICTION_SERVICE}/{layer}",
                {
                    "where": "1=1",
                    "outFields": "*",
                    "geometry": f"{box.west},{box.south},{box.east},{box.north}",
                    "geometryType": "esriGeometryEnvelope",
                    "inSR": "4326",
                    "spatialRel": "esriSpatialRelIntersects",
                    "maxAllowableOffset": "0.0002",
                },
                record=record,
                page_size=500,
            )
            for feature in features:
                feature.setdefault("properties", {})["_layer"] = kind
            found.extend(features)
        path.write_text(json.dumps({"type": "FeatureCollection", "features": found}))
        record.add_file(path, root=directory)
        fetched += 1
    _write_record(record, directory)
    print(f"    {RESTRICTIONS}: {fetched} parks fetched")


# MARK: - Counties


def _fetch_counties(session: httpx.Client, version: str, *, refresh: bool) -> None:
    directory = rawstore.version_directory(COUNTIES, version)
    path = directory / COUNTIES_FILE
    if _skip(path, refresh):
        print(f"    {COUNTIES}: already fetched today")
        return
    record = FetchRecord(source=COUNTY_TERMS, fetched_at=rawstore.utc_now())
    response = http.get(session, COUNTIES_URL, expect="application")
    path.write_bytes(response.content)
    record.add_request(COUNTIES_URL)
    record.add_file(path, root=directory)
    _write_record(record, directory)
    print(f"    {COUNTIES}: {len(read_counties(path))} counties")


def read_counties(path: Path) -> dict[str, list[outline.Polygon]]:
    """County number → its polygons, from the zipped GeoJSON as Kartverket publishes it.
    The file also holds the boundary lines between counties; only ``Fylke`` features
    are counties."""
    with zipfile.ZipFile(path) as archive:
        name = next(n for n in archive.namelist() if n.lower().endswith(".geojson"))
        payload = json.load(io.TextIOWrapper(archive.open(name), encoding="utf-8-sig"))
    counties: dict[str, list[outline.Polygon]] = {}
    for feature in payload.get("features") or []:
        properties = feature.get("properties") or {}
        if properties.get("objtype") != "Fylke":
            continue
        code = str(properties.get("fylkesnummer") or "").zfill(2)
        counties.setdefault(code, []).extend(outline.polygons_of(feature.get("geometry")))
    return counties


# MARK: - Wikidata, Wikipedia and Commons


def _sparql(session: httpx.Client, query: str, record: FetchRecord) -> dict[str, Any]:
    politeness = http.Politeness(attempts=4, backoff_seconds=10.0, pause_seconds=2.0)
    response = http.get(
        session, SPARQL, params={"query": query, "format": "json"},
        politeness=politeness, expect="application/sparql-results+json",
    )
    record.add_request(SPARQL, {"query": query})
    return response.json()


def _fetch_wikidata(session: httpx.Client, version: str, *, refresh: bool) -> None:
    directory = rawstore.version_directory(WIKIDATA, version)
    record = FetchRecord(source=WIKIDATA_TERMS, fetched_at=rawstore.utc_now())
    for name, query in (("naturbase.json", NATURBASE_QUERY), ("candidates.json", CANDIDATE_QUERY)):
        path = directory / name
        if _skip(path, refresh):
            continue
        payload = _sparql(session, query, record)
        path.write_text(json.dumps(payload, ensure_ascii=False))
        record.add_file(path, root=directory)
        rows = len((payload.get("results") or {}).get("bindings") or [])
        print(f"    {WIKIDATA}/{name}: {rows} rows")
    _write_record(record, directory)


def read_wikidata(
    directory: Path | None,
) -> tuple[dict[str, dict[str, Any]], list[dict[str, Any]]]:
    """The Naturbase index and the name-and-location candidates, or empty ones."""
    def bindings(name: str) -> list[dict[str, Any]]:
        path = directory / name if directory else None
        if not path or not path.exists():
            return []
        return (json.loads(path.read_text()).get("results") or {}).get("bindings") or []

    return wiki.naturbase_index(bindings("naturbase.json")), wiki.candidates(
        bindings("candidates.json")
    )


def wiki_matches(
    areas: dict[str, Area], index: dict[str, dict[str, Any]], others: list[dict[str, Any]]
) -> dict[str, dict[str, Any]]:
    """``naturvernId`` → the Wikidata item that is the place's own, for the national parks
    and the second tier matched together (``wiki.own_matches``), so a park's item is
    never given to the landscape or reserve beside it."""
    parks = [area for _, area in national_parks(areas) if area is not None]
    return wiki.own_matches(
        (
            (area.naturvern_id, area.tier, area.name, area.centre)
            for area in [*parks, *second_tier(areas)]
        ),
        index,
        others,
    )


def _second_tier_matches(
    wikidata_dir: Path, areas: dict[str, Area]
) -> dict[str, dict[str, Any]]:
    """``naturvernId`` → Wikidata item, for each second-tier place that has its own."""
    index, others = read_wikidata(wikidata_dir)
    found = wiki_matches(areas, index, others)
    matches = {
        area.naturvern_id: found[area.naturvern_id]
        for area in second_tier(areas)
        if area.naturvern_id in found
    }
    with_article = sum(1 for item in matches.values() if item.get("article"))
    print(
        f"    {WIKIDATA}: {len(matches)} of {len(second_tier(areas))} landscapes and "
        f"reserves matched, {with_article} with an English article"
    )
    return matches


def _load(path: Path, refresh: bool) -> dict[str, Any]:
    if refresh or not path.exists():
        return {}
    return json.loads(path.read_text())


def wikimedia_get(
    session: httpx.Client, url: str, parameters: dict[str, str]
) -> dict[str, Any] | None:
    """One Wikimedia API call, waiting out a refusal for as long as the server's
    ``Retry-After`` asks (Wikimedia meters clients that carry no contact address hard),
    up to six times."""
    for attempt in range(6):
        try:
            response = session.get(url, params=parameters)
        except httpx.HTTPError:
            time.sleep(10 * (attempt + 1))
            continue
        if response.status_code == 429 or response.status_code >= 500:
            retry_after = response.headers.get("retry-after") or ""
            wait = float(retry_after) if retry_after.isdigit() else 15.0 * (attempt + 1)
            time.sleep(min(wait + 1, 120))
            continue
        if response.status_code != 200 or "json" not in response.headers.get("content-type", ""):
            return None
        time.sleep(1.0)
        return response.json()
    return None


def _chunks(items: list[Any], size: int) -> list[list[Any]]:
    return [items[start:start + size] for start in range(0, len(items), size)]


def _resolved(query: dict[str, Any], title: str) -> str:
    """A title as the API files it, after its normalisation and any redirect."""
    for key in ("normalized", "redirects"):
        for step in query.get(key) or []:
            if step.get("from") == title:
                title = step.get("to") or title
    return title


def _fetch_wikipedia(
    session: httpx.Client, version: str, matches: dict[str, dict[str, Any]], *, refresh: bool
) -> None:
    """The English lead of each matched article, twenty to a request through the Action
    API: the REST summary endpoint turns away clients without a contact address."""
    directory = rawstore.version_directory(WIKIPEDIA, version)
    path = directory / "summaries.json"
    summaries = _load(path, refresh)
    record = FetchRecord(source=WIKIPEDIA_TERMS, fetched_at=rawstore.utc_now())
    wanted = [
        (naturvern, title)
        for naturvern, item in sorted(matches.items())
        if (title := wiki.article_title(item.get("article"))) and naturvern not in summaries
    ]
    for batch in _chunks(wanted, 20):
        parameters = {
            "action": "query",
            "format": "json",
            "formatversion": "2",
            "prop": "extracts|info|pageprops",
            "exintro": "1",
            "explaintext": "1",
            "inprop": "url",
            "ppprop": "disambiguation",
            "redirects": "1",
            "titles": "|".join(title for _, title in batch),
        }
        payload = wikimedia_get(session, WIKIPEDIA_API, parameters)
        if payload is None:
            print(f"    {WIKIPEDIA}: a batch of {len(batch)} failed; run again to resume")
            continue
        record.add_request(WIKIPEDIA_API, parameters)
        query = payload.get("query") or {}
        pages = {page.get("title"): page for page in query.get("pages") or []}
        for naturvern, title in batch:
            page = pages.get(_resolved(query, title))
            if not page or page.get("missing") or not page.get("extract"):
                continue
            summaries[naturvern] = {
                "title": page["title"],
                "pageid": page.get("pageid"),
                "type": "disambiguation"
                if "disambiguation" in (page.get("pageprops") or {})
                else "standard",
                "extract": page["extract"],
                "content_urls": {"desktop": {"page": page.get("fullurl")}},
            }
        path.write_text(json.dumps(summaries, ensure_ascii=False, indent=1))
    path.write_text(json.dumps(summaries, ensure_ascii=False, indent=1))
    record.add_file(path, root=directory)
    _write_record(record, directory)
    print(f"    {WIKIPEDIA}: {len(summaries)} summaries ({len(wanted)} asked for now)")


def _fetch_commons(
    session: httpx.Client, version: str, matches: dict[str, dict[str, Any]], *, refresh: bool
) -> None:
    """Licence and author for every photograph a guide names and every second-tier
    place's P18 image, fifty files to a request. Each record has the shape
    ``common.commons_licence`` gives, which asks once per file."""
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
    for batch in _chunks(pending, 50):
        parameters = {
            "action": "query",
            "format": "json",
            "formatversion": "2",
            "prop": "imageinfo",
            "iiprop": "extmetadata|url|user",
            "iiurlwidth": "1280",
            "titles": "|".join(f"File:{name}" for name in batch),
        }
        payload = wikimedia_get(session, COMMONS_API, parameters)
        if payload is None:
            print(f"    {COMMONS}: a batch of {len(batch)} failed; run again to resume")
            continue
        record.add_request(COMMONS_API, {**parameters, "titles": f"{len(batch)} files"})
        query = payload.get("query") or {}
        pages = {page.get("title"): page for page in query.get("pages") or []}
        for name in batch:
            page = pages.get(_resolved(query, f"File:{name}")) or {}
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
    path.write_text(json.dumps(licences, ensure_ascii=False, indent=1))
    record.add_file(path, root=directory)
    _write_record(record, directory)
    missing = sum(1 for name in wanted if not licences.get(name))
    print(f"    {COMMONS}: {len(wanted)} files, {len(pending)} asked for now, {missing} not found")


def file_path_url(name: str, width: int | None = None) -> str:
    """The Commons URL that names a file, optionally as a thumbnail ``width`` wide."""
    url = COMMONS_FILE_PATH + quote(name.replace(" ", "_"), safe="")
    return f"{url}?width={width}" if width else url


def photo_url(name: str) -> str:
    """Where a guide photograph is downloaded from, and so its name in the raw store."""
    return file_path_url(name, PHOTO_WIDTH)


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


_PDF = re.compile(r"""(?:https?://[^\s"'<>]+|/[^\s"'<>]+)\.pdf(?:\?[^\s"'<>]*)?""", re.IGNORECASE)
_ANCHOR = re.compile(r"""<a[^>]+href=["']([^"']+\.pdf[^"']*)["'][^>]*>(.*?)</a>""", re.I | re.S)


def _portal_json(session: httpx.Client, url: str) -> dict[str, Any] | None:
    """A norgesnasjonalparker.no page through the site's own content API: the page URL
    asked for as JSON, the way the site's own scripts read it."""
    try:
        response = session.get(
            url, headers={"Accept": "application/json", "Accept-Language": "no"}
        )
    except httpx.HTTPError as error:
        print(f"    {DOCUMENTS}: {url} failed ({error})")
        return None
    time.sleep(http.DEFAULT_POLITENESS.pause_seconds)
    if response.status_code != 200 or "json" not in response.headers.get("content-type", ""):
        print(f"    {DOCUMENTS}: {url} answered {response.status_code}")
        return None
    return response.json()


def park_pages(listing: dict[str, Any] | None, areas: dict[str, Area]) -> dict[str, str]:
    """Park id → its page on norgesnasjonalparker.no: the guide's first source there, or
    the listing's card for the park (Svalbard's seven share one page)."""
    cards: dict[str, str] = {}
    for card in (listing or {}).get("listCards") or []:
        title = (card.get("title") or "").strip().lower()
        url = next(
            (link.get("url") for link in card.get("links") or [] if link.get("url")), None
        )
        if title and url:
            cards[rules.strip_designation(title)] = urljoin(PORTAL + "/", url)
    pages: dict[str, str] = {}
    for park in content.parks():
        if url := content.first_source_url(park["id"]):
            pages[park["id"]] = url
            continue
        if park.get("svalbard"):
            if url := cards.get(SVALBARD_CARD):
                pages[park["id"]] = url
            continue
        area = areas.get(park["naturvernId"])
        names = {park["name"].lower()}
        if area:
            names.add(area.name.lower())
            names.update(part.strip() for part in area.name.lower().split("/"))
        if url := next((cards[name] for name in names if name in cards), None):
            pages[park["id"]] = url
    return pages


def pdf_links(page: dict[str, Any]) -> list[dict[str, str]]:
    """Every PDF a page's content links, absolute, with the link's own text as its title
    where the page gives one."""
    titles: dict[str, str] = {}

    def walk(node: Any) -> None:
        if isinstance(node, dict):
            url, text = node.get("url"), node.get("text") or node.get("title")
            if isinstance(url, str) and _PDF.fullmatch(url.strip()) and isinstance(text, str):
                titles.setdefault(urljoin(PORTAL + "/", url.strip()), text.strip())
            for value in node.values():
                walk(value)
        elif isinstance(node, list):
            for value in node:
                walk(value)
        elif isinstance(node, str) and ".pdf" in node.lower():
            for href, text in _ANCHOR.findall(node):
                label = re.sub(r"<[^>]+>|\s+", " ", text).strip()
                if label:
                    titles.setdefault(urljoin(PORTAL + "/", href.strip()), label)

    walk(page)
    found: list[dict[str, str]] = []
    seen: set[str] = set()
    for match in _PDF.finditer(json.dumps(page, ensure_ascii=False)):
        url = urljoin(PORTAL + "/", match.group(0).replace("\\/", "/"))
        if url in seen:
            continue
        seen.add(url)
        title = titles.get(url) or url.rsplit("/", 1)[-1].rsplit(".", 1)[0].replace("-", " ")
        found.append({"title": title, "url": url})
    return found


def _fetch_documents(
    session: httpx.Client, version: str, areas: dict[str, Area], *, refresh: bool
) -> None:
    directory = rawstore.version_directory(DOCUMENTS, version)
    pages_dir = directory / "pages"
    pages_dir.mkdir(exist_ok=True)
    record = FetchRecord(source=DOCUMENT_TERMS, fetched_at=rawstore.utc_now())
    listing_path = directory / "listing.json"
    if _skip(listing_path, refresh):
        listing = json.loads(listing_path.read_text())
    else:
        listing = _portal_json(session, PORTAL_LIST)
        if listing is not None:
            listing_path.write_text(json.dumps(listing, ensure_ascii=False))
            record.add_request(PORTAL_LIST, {"Accept": "application/json"})
            record.add_file(listing_path, root=directory)
    pages = park_pages(listing, areas)
    heads_path = directory / "heads.json"
    heads: dict[str, Any] = _load(heads_path, refresh)
    read: dict[str, dict[str, Any] | None] = {}

    def page_at(url: str, path: Path) -> dict[str, Any] | None:
        """A page, from today's store or the site; Svalbard's seven parks share one."""
        if _skip(path, refresh):
            return json.loads(path.read_text())
        if url not in read:
            read[url] = _portal_json(session, url)
            record.add_request(url, {"Accept": "application/json"})
        page = read[url]
        if page is not None:
            path.write_text(json.dumps(page, ensure_ascii=False))
            record.add_file(path, root=directory)
        return page

    links: dict[str, Any] = {}
    for park in content.parks():
        url = pages.get(park["id"])
        if not url:
            print(f"    {DOCUMENTS}: no page found for {park['id']}")
            continue
        page = page_at(url, pages_dir / f"{park['id']}.json") or {}
        english = next(
            (
                other["link"]
                for other in page.get("existingLanguages") or []
                if other.get("name") == "en" and other.get("link")
            ),
            None,
        )
        # Links found on the Norwegian page are taken to be in Norwegian unless they
        # say otherwise; links on the English page, in English.
        candidates = [(link, "no") for link in pdf_links(page)]
        if english:
            english_page = page_at(english, pages_dir / f"{park['id']}.en.json") or {}
            candidates.extend((link, None) for link in pdf_links(english_page))
        entry: dict[str, Any] = {"page": url, "english": english, "documents": []}
        seen: set[str] = set()
        for link, language in candidates:
            if link["url"] not in heads:
                heads[link["url"]] = _head(session, link["url"])
                record.add_request(link["url"], {"method": "HEAD"})
            head = heads[link["url"]]
            # One document linked under two names (a renamed host) is listed once.
            final = head.get("url") or link["url"]
            if not head.get("ok") or final in seen:
                continue
            seen.add(final)
            document = {"title": document_title(link), "url": final}
            if head.get("bytes"):
                document["bytes"] = head["bytes"]
            if _says_norwegian(link) or (language and not _says_english(link)):
                document["language"] = "no"
            entry["documents"].append(document)
        links[park["id"]] = entry
    heads_path.write_text(json.dumps(heads, ensure_ascii=False, indent=1))
    links_path = directory / "links.json"
    links_path.write_text(json.dumps(links, ensure_ascii=False, indent=1))
    record.add_file(links_path, root=directory)
    _write_record(record, directory)
    documents = sum(len(entry["documents"]) for entry in links.values())
    print(f"    {DOCUMENTS}: {len(links)} park pages, {documents} PDFs that answer")


_GENERIC_LINK = re.compile(
    r"^(les mer|read more|her|here|last ned|download|klikk her|click here|pdf)\b", re.I
)


def document_title(link: dict[str, str]) -> str:
    """The link's own text, unless it is "Les mer her" or "Read more", in which case the
    file's name says more."""
    title = link["title"].strip()
    if title and not _GENERIC_LINK.match(title):
        return title
    stem = link["url"].rsplit("/", 1)[-1].rsplit(".", 1)[0]
    words = re.sub(r"[-_]+", " ", stem).strip()
    return words[:1].upper() + words[1:] if words else title


def _says_norwegian(link: dict[str, str]) -> bool:
    return bool(re.search(r"\(in norwegian\)|på norsk|norwegian only", link["title"], re.I))


def _says_english(link: dict[str, str]) -> bool:
    text = f"{link['title']} {link['url'].rsplit('/', 1)[-1]}".lower()
    return bool(re.search(r"\b(english|engelsk)\b|[-_ ]en\b", text))


def _head(session: httpx.Client, url: str) -> dict[str, Any]:
    """Whether a PDF link answers, where it lands and how big it is."""
    try:
        response = session.head(url)
    except httpx.HTTPError as error:
        return {"ok": False, "problem": f"{type(error).__name__}: {error}"}
    time.sleep(http.DEFAULT_POLITENESS.pause_seconds)
    content_type = response.headers.get("content-type", "")
    ok = response.status_code == 200 and ("pdf" in content_type or "octet" in content_type)
    result: dict[str, Any] = {"ok": ok, "status": response.status_code, "url": str(response.url)}
    length = response.headers.get("content-length") or ""
    if length.isdigit():
        result["bytes"] = int(length)
    return result


# MARK: - OpenStreetMap


# Huts, railway stations and the stop areas they belong to, one query per region of the
# country. Asked park by park this took fifty queries; the public servers queue every one
# of them, and at busy hours each waited minutes. A region's answer is small (a few
# thousand points), and the build keeps the huts inside each park and the stations within
# 100 km of one.
REGION_QUERY = """[out:json][timeout:600];
nwr["tourism"~"^(alpine_hut|wilderness_hut)$"]({box});
out center tags;
{stations}"""

STATION_PART = """(
  nwr["railway"~"^(station|halt)$"]({box});
  nwr["public_transport"="station"]["train"="yes"]({box});
)->.stations;
.stations out center tags;
(
  rel(bn.stations)["public_transport"="stop_area"];
  rel(bw.stations)["public_transport"="stop_area"];
);
out body;
"""

# Norway's passenger rail routes, by the same regions: one query with an area filter for
# the whole country runs past the public servers' time limits. Routes reaching into Sweden
# come back whole; the build keeps those that stop in Norway.
RAIL_ROUTE_QUERY = """[out:json][timeout:600];
rel["route"="train"]({box});
out geom;
"""
# South, west, north, east. The mainland's three overlap a little; Svalbard has no railway.
REGIONS = {
    "south": (57.9, 4.4, 61.0, 12.9),
    "middle": (61.0, 4.4, 64.5, 14.5),
    "north": (64.5, 11.0, 71.3, 31.2),
}
SVALBARD_REGION = (76.3, 9.0, 80.9, 35.0)

# The public Overpass servers turn automated work away when they are full. VK's mirror
# answers the same API; it is asked first, and the shared list after it.
OVERPASS_ENDPOINTS = ("https://maps.mail.ru/osm/tools/overpass/api/interpreter", *osm.ENDPOINTS)
OVERPASS_GIVE_UP = 2


def _box(box: tuple[float, float, float, float]) -> str:
    return ",".join(f"{value:.5f}" for value in box)


def region_query(box: tuple[float, float, float, float], *, stations: bool) -> str:
    """Huts in a region and, on the mainland, its railway stations with their stop
    areas."""
    part = STATION_PART.format(box=_box(box)) if stations else ""
    return REGION_QUERY.format(box=_box(box), stations=part)


def osm_jobs(directory: Path, refresh: bool) -> list[tuple[str, Path, str]]:
    """``(name, file, query)`` for every Overpass answer the build reads that today's
    store does not hold yet."""
    jobs: list[tuple[str, Path, str]] = []
    # The rail routes first: without them there is no rail layer at all, while a region's
    # huts and stations missing costs only that region's.
    for name, box in REGIONS.items():
        path = directory / f"rail-routes-{name}.json"
        if not _skip(path, refresh):
            jobs.append((f"rail-routes-{name}", path, RAIL_ROUTE_QUERY.format(box=_box(box))))
    regions = {**{name: (box, True) for name, box in REGIONS.items()},
               "svalbard": (SVALBARD_REGION, False)}
    for name, (box, stations) in regions.items():
        path = directory / "regions" / f"{name}.json"
        if not _skip(path, refresh):
            jobs.append((f"region-{name}", path, region_query(box, stations=stations)))
    return jobs


def _fetch_osm(session: httpx.Client, version: str, *, refresh: bool) -> None:
    directory = rawstore.version_directory(OSM, version)
    (directory / "regions").mkdir(exist_ok=True)
    record = FetchRecord(source=OSM_TERMS, fetched_at=rawstore.utc_now())
    failed: list[str] = []
    refused_in_a_row = 0
    # A server that will not even connect is passed over in seconds, not minutes.
    overpass = httpx.Client(
        headers=dict(session.headers),
        timeout=httpx.Timeout(150.0, connect=10.0),
        follow_redirects=True,
    )
    for name, path, query in osm_jobs(directory, refresh):
        # Every server refused twice running: Overpass is full, and asking for the rest
        # now only lengthens its queue. A later run resumes from here.
        if refused_in_a_row >= OVERPASS_GIVE_UP:
            failed.append(name)
            continue
        try:
            payload = osm.download_query(
                overpass, query, record=record, endpoints=OVERPASS_ENDPOINTS
            )
        except http.FetchError as error:
            print(f"    {OSM}: {name} failed ({error})")
            failed.append(name)
            refused_in_a_row += 1
            continue
        refused_in_a_row = 0
        path.write_text(json.dumps(payload, ensure_ascii=False))
        record.add_file(path, root=directory)
        print(f"    {OSM}: {name} {len(payload.get('elements') or [])} elements", flush=True)
        # Overpass is volunteer-run: a breath between queries.
        time.sleep(5)
    overpass.close()
    _write_record(record, directory)
    if failed:
        print(f"    {OSM}: not fetched, run again to resume: {', '.join(failed)}")


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
