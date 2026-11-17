"""Fetching Japan's sources into the raw store.

Every source lands in ``raw/<date>/jp-<source>/`` with a ``source.json`` recording what
was asked for, under which terms, and what came back. Each step skips what today's
snapshot already holds, so an interrupted fetch picks up where it stopped; ``refresh``
fetches again. The ``jp-`` prefix keeps these apart from the US's own ``climate``,
``wikipedia`` and ``transport`` folders, which the US build finds by name.

``jp-biodic/``
    The Ministry of the Environment's national park zones (``nps.zip``), snapshotted with
    its ``Last-Modified``, and each park's zones merged by class under ``zones/`` for a
    later zone map. The file is orphaned — no Ministry page links it any more (sources
    note J-1) — so the snapshot is the copy that matters.
``jp-natural-earth/``
    Natural Earth's admin-1 file, and Japan's 47 prefectures read out of it.
``jp-moe/``
    The quasi-national park list, the regional office page, and the visitor statistics
    (表Ⅱ-1, park visitors; 表Ⅱ-9, visitor centres) for 2024.
``jp-wikidata/``, ``jp-wikipedia/``, ``jp-commons/``
    Every park's Wikidata item; English Wikipedia leads for the quasi-national parks;
    Commons licence metadata for the guides' photographs and the parks' lead images, and
    the guides' photographs themselves.
``jp-climate/``
    Ten years of Open-Meteo daily weather at each national park's centre (``climate``).
``jp-osm/``
    Quasi-national park outlines, every passenger rail service, and per national park
    its huts and the stations within 100 km.
``jp-documents/``
    The Ministry's English brochures and each park's page on japan.travel, every PDF
    checked with a request before it is recorded.
"""

from __future__ import annotations

import json
import math
import time
import zipfile
from pathlib import Path
from typing import Any
from urllib.parse import quote

import httpx

from ... import __version__, climate, config, outline, rawstore
from ...rawstore import FetchRecord, SourceTerms
from ...sources import http
from ..common import commons_licence, photo_filename
from . import content, geometry, moe, shapefile

# Names the app and no person. Wikimedia asks for a descriptive agent; this is one.
USER_AGENT = (
    f"unigrids-pipeline/{__version__} (offline reference-data builder for the Unigrids app)"
)

BIODIC = "jp-biodic"
NATURAL_EARTH = "jp-natural-earth"
MOE = "jp-moe"
WIKIDATA = "jp-wikidata"
WIKIPEDIA = "jp-wikipedia"
COMMONS = "jp-commons"
CLIMATE = "jp-climate"
OSM = "jp-osm"
DOCUMENTS = "jp-documents"

NPS_ZIP_URL = "https://www.biodic.go.jp/shapedata/nps.zip"
NPS_ZIP = "nps.zip"
NPS_ARCHIVED_PAGE = (
    "http://web.archive.org/web/20260609214911/https://www.biodic.go.jp/nps_nwp_nca_cz.html"
)
NATURAL_EARTH_URL = (
    "https://naturalearth.s3.amazonaws.com/10m_cultural/ne_10m_admin_1_states_provinces.zip"
)
NATURAL_EARTH_ZIP = "ne_10m_admin_1_states_provinces.zip"
PREFECTURES_FILE = "prefectures.geojson"
WIKIDATA_SPARQL = "https://query.wikidata.org/sparql"
WIKIDATA_FILE = "parks.json"
WIKI_SUMMARY = "https://en.wikipedia.org/api/rest_v1/page/summary/"
SUMMARIES_FILE = "summaries.json"
LICENCES_FILE = "licences.json"
COMMONS_FILE_PATH = "https://commons.wikimedia.org/wiki/Special:FilePath/"
# Wikimedia serves thumbnails in fixed steps; 1920 is the one above the hero's 1600.
PHOTO_WIDTH = 1920
QUASI_OUTLINES_FILE = "quasi-outlines.json"
DOCUMENTS_FILE = "documents.json"

# The national park (国立公園) and quasi-national park (国定公園) classes on Wikidata.
# Wikidata holds 60 quasi-national items against the Ministry's 58 (sources note B-2), so
# items are matched to the official list by name and never selected by class alone.
NATIONAL_PARK_CLASS = "Q1071482"
QUASI_NATIONAL_PARK_CLASS = "Q11832860"

# How far around a park the stations reach.
STATION_REACH_KM = 100.0

# Passenger rail is fetched by region, so one busy Overpass instance never has to answer
# for the whole country at once. South, west, north, east.
RAIL_REGIONS: dict[str, tuple[float, float, float, float]] = {
    "hokkaido": (41.3, 139.3, 45.6, 145.9),
    "tohoku": (36.8, 139.1, 41.6, 142.1),
    "kanto": (34.8, 138.3, 37.2, 141.0),
    "chubu": (34.5, 135.9, 37.9, 139.3),
    "kinki": (33.4, 134.2, 35.8, 136.4),
    "chugoku-shikoku": (32.6, 130.8, 36.0, 134.8),
    "kyushu": (30.9, 128.5, 34.3, 132.1),
    "southwest-islands": (24.0, 122.9, 30.9, 131.4),
}

BIODIC_TERMS = SourceTerms(
    identifier="moe-biodic-nps",
    title="国立公園区域等 (national park areas and zones), MOE Biodiversity Center",
    url=NPS_ZIP_URL,
    licence="Public Data License 1.0 (PDL 1.0), MOE Biodiversity Center terms",
    attribution=(
        "出典：「国立公園区域等」（環境省生物多様性センター）"
        "https://www.biodic.go.jp/shapedata/nps.zip。Unigrids が簡略化・加工して作成"
    ),
    notes=(
        "Snapshot of an orphaned file: no Ministry page links it since the Web-GIS closed in "
        f"May 2026 (archived listing: {NPS_ARCHIVED_PAGE}). MOE's caveat: 本データは、指定区域"
        "の概要を示すために作成したものであり、誤差を含みます。 The outlines are not legal "
        "boundaries. zones/ holds each park's zones merged by class, derived here."
    ),
)
NATURAL_EARTH_TERMS = SourceTerms(
    identifier="natural-earth-admin1",
    title="Natural Earth 1:10m admin-1 states and provinces (Japan's prefectures)",
    url=NATURAL_EARTH_URL,
    licence="Public domain",
    attribution="Made with Natural Earth",
    notes="prefectures.geojson is Japan's 47 features read out of the zip, unchanged.",
)
MOE_TERMS = SourceTerms(
    identifier="moe-japan",
    title="Ministry of the Environment: quasi-national park list, offices, visitor statistics",
    url="https://www.env.go.jp/park/",
    licence="Public Data License 1.0 (PDL 1.0), https://www.env.go.jp/mail.html",
    attribution=(
        "出典：環境省ホームページ；「自然公園等利用者数調」（環境省）"
        f"（{moe.STATISTICS_PAGE}）"
    ),
    notes="Visitor figures are 令和6年 (2024), in units of 10,000 visitors as published.",
)
WIKIDATA_TERMS = SourceTerms(
    identifier="wikidata-jp-parks",
    title="Wikidata items for Japan's national and quasi-national parks",
    url=WIKIDATA_SPARQL,
    licence="CC0",
    attribution="Wikidata",
    notes="A cross-check and a source of sitelinks, images and coordinates; matched by name.",
)
WIKIPEDIA_TERMS = SourceTerms(
    identifier="wikipedia-jp-quasi",
    title="English Wikipedia lead summaries for Japan's quasi-national parks",
    url="https://en.wikipedia.org/api/rest_v1/",
    licence="CC BY-SA 4.0",
    attribution="Summaries: Wikipedia, CC BY-SA 4.0, linked from each place",
)
COMMONS_TERMS = SourceTerms(
    identifier="commons-jp",
    title="Wikimedia Commons licence metadata and photographs for Japan's parks",
    url="https://commons.wikimedia.org/w/api.php",
    licence="Each file under its own licence, recorded beside it",
    attribution="Photographs credited individually, via Wikimedia Commons",
    notes=(
        "Licences are not a reason to leave a photograph out of this private app (the "
        "owner's decision); every photograph keeps its credit and licence."
    ),
)
OSM_TERMS = SourceTerms(
    identifier="openstreetmap-jp",
    title="OpenStreetMap via Overpass: quasi-national park outlines, huts, rail",
    url="https://www.openstreetmap.org/copyright",
    licence="Open Database License (ODbL) 1.0",
    attribution="© OpenStreetMap contributors",
    notes=(
        "Outlines, huts, stations and rail lines ship as data, so the dataset is a "
        "Derivative Database under the ODbL and owes attribution and share-alike."
    ),
)
DOCUMENTS_TERMS = SourceTerms(
    identifier="moe-brochures",
    title="Ministry of the Environment brochures on japan.travel",
    url=moe.BROCHURE_URL,
    licence="japan.travel terms: compatible with CC BY 4.0, commercial use permitted",
    attribution="Source: Ministry of the Environment website",
    notes="Linked and shown as published; nothing is extracted from them.",
)


def fetch(*, refresh: bool = False) -> Path:
    """Fetch everything Japan's assembly reads into ``raw/<today>/``."""
    version = rawstore.today()
    root = config.RAW_DIR / version
    parks = content.national_parks()

    outlines = fetch_biodic(version, parks, refresh=refresh)
    fetch_natural_earth(version, refresh=refresh)
    quasi = fetch_moe(version, refresh=refresh)
    items = fetch_wikidata(version, refresh=refresh)
    fetch_wikipedia(version, quasi, items, refresh=refresh)
    fetch_commons(version, parks, quasi, items, refresh=refresh)
    centres = {
        park["id"]: outline.label_point(polygons)
        for park in parks
        if (polygons := outlines.get(park["id"]))
    }
    with client() as session:
        climate.fetch_points(
            {key: value for key, value in centres.items() if value},
            version, source=CLIMATE, refresh=refresh, session=session,
        )
    fetch_documents(version, parks, refresh=refresh)
    # Last, because Overpass is the slowest and the busiest: everything else is in hand
    # if it gives up, and a second run resumes with the queries it did not answer.
    fetch_osm(version, parks, outlines, quasi, items, refresh=refresh)
    # Trails from OpenStreetMap, one park at a time; a park Overpass does not answer is
    # named and left for the next run.
    from ..abroad import outlines as abroad_outlines
    from ..abroad import trails as abroad_trails

    abroad_trails.fetch(
        "jp", list(abroad_outlines.park_list("jp")), abroad_outlines.outlines("jp"),
        refresh=refresh,
    )
    return root


# MARK: - Shared


def client(politeness: http.Politeness = http.DEFAULT_POLITENESS) -> httpx.Client:
    """The shared client's habits under Japan's own User-Agent."""
    return httpx.Client(
        headers={"User-Agent": USER_AGENT},
        timeout=politeness.timeout_seconds,
        follow_redirects=True,
    )


def _record_write(record: FetchRecord, directory: Path) -> None:
    """Write ``source.json``, keeping what an earlier partial fetch the same day
    recorded, so a resumed fetch still lists everything it holds."""
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


def _download(
    session: httpx.Client, url: str, path: Path, record: FetchRecord, *, note: str = ""
) -> dict[str, str]:
    """Stream ``url`` to ``path`` and record it; returns the response headers worth
    keeping (``Last-Modified``, ``ETag``, size)."""
    path.parent.mkdir(parents=True, exist_ok=True)
    partial = path.with_name(path.name + ".part")
    for attempt in range(4):
        if attempt:
            time.sleep(5 * 2**attempt)
        try:
            with session.stream("GET", url) as response:
                if response.status_code in http.RETRY_STATUS:
                    continue
                response.raise_for_status()
                with partial.open("wb") as handle:
                    for chunk in response.iter_bytes(1 << 20):
                        handle.write(chunk)
                headers = {
                    key: response.headers[key]
                    for key in ("last-modified", "etag", "content-length", "content-type")
                    if key in response.headers
                }
            break
        except httpx.HTTPError as error:
            print(f"    {url}: {error}; retrying")
    else:
        raise http.FetchError(f"{url} failed after 4 attempts")
    partial.replace(path)
    record.add_request(url, headers=headers)
    record.add_file(path, root=record_root(path), note=note)
    time.sleep(http.DEFAULT_POLITENESS.pause_seconds)
    return headers


def record_root(path: Path) -> Path:
    """The source directory a raw file belongs to: ``raw/<date>/<source>/``."""
    for parent in path.parents:
        if parent.parent.parent == config.RAW_DIR:
            return parent
    return path.parent


def _head(session: httpx.Client, url: str) -> httpx.Response | None:
    try:
        response = session.head(url)
    except httpx.HTTPError:
        return None
    time.sleep(http.DEFAULT_POLITENESS.pause_seconds)
    return response


def _wanted(path: Path, refresh: bool) -> bool:
    if path.exists() and not refresh:
        print(f"    {path.parent.name}/{path.name}: already fetched today, leaving it alone")
        return False
    return True


# MARK: - National park zones


def fetch_biodic(
    version: str, parks: list[dict[str, Any]], *, refresh: bool
) -> dict[str, list[outline.Polygon]]:
    """Snapshot ``nps.zip`` and return each national park's outline, its zones merged."""
    directory = rawstore.version_directory(BIODIC, version)
    record = FetchRecord(source=BIODIC_TERMS, fetched_at=rawstore.utc_now())
    path = directory / NPS_ZIP
    with client() as session:
        if _wanted(path, refresh):
            headers = _download(session, NPS_ZIP_URL, path, record)
            print(f"    {BIODIC}: nps.zip, {path.stat().st_size:,} bytes, "
                  f"Last-Modified {headers.get('last-modified')}")
        elif not (directory / "source.json").exists():
            # Fetched by hand or by an interrupted run: still record where it came from.
            head = _head(session, NPS_ZIP_URL)
            headers = dict(head.headers) if head is not None else {}
            record.add_request(NPS_ZIP_URL, method="HEAD", headers={
                key: headers[key] for key in ("last-modified", "etag", "content-length")
                if key in headers
            })
            record.add_file(path, root=directory)
    zones = park_zones(path, parks)
    outlines = {park_id: outline_of(by_zone) for park_id, by_zone in zones.items()}
    zones_dir = directory / "zones"
    for park_id, by_zone in zones.items():
        target = zones_dir / f"{park_id}.geojson"
        if target.exists() and not refresh:
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        features = [
            {
                "type": "Feature",
                "properties": {"zone": zone, "park": park_id},
                "geometry": _multipolygon(geometry.union(polygons)),
            }
            for zone, polygons in sorted(by_zone.items())
        ]
        target.write_text(json.dumps(
            {"type": "FeatureCollection", "features": features}, ensure_ascii=False
        ))
        record.add_file(target, root=directory, note=f"{park_id}: zones merged by class")
    _record_write(record, directory)
    print(f"    {BIODIC}: {len(outlines)} national park outlines from their zones")
    return outlines


def park_zones(
    path: Path, parks: list[dict[str, Any]]
) -> dict[str, dict[str, list[outline.Polygon]]]:
    """Park ID → zone class (``特別保護地区``…) → its polygons, from ``nps.zip``.

    The file names each park as its content entry's Japanese name without
    ``国立公園``; every one of the 35 must be there, and nothing else.
    """
    by_name = {content.short_name(park): park["id"] for park in parks}
    result: dict[str, dict[str, list[outline.Polygon]]] = {}
    unknown: set[str] = set()
    for feature in shapefile.read_zip(path):
        name = str(feature.attributes.get("NAME") or "").strip()
        park_id = by_name.get(name)
        if park_id is None:
            unknown.add(name)
            continue
        zone = str(feature.attributes.get("ZONE") or "").strip() or "区分なし"
        result.setdefault(park_id, {}).setdefault(zone, []).extend(feature.polygons)
    missing = sorted(set(by_name) - {name for name, pid in by_name.items() if pid in result})
    if unknown or missing:
        raise shapefile.ShapefileError(
            f"nps.zip names parks the content list does not ({sorted(unknown)}) or lacks "
            f"some it does ({missing})"
        )
    return result


def outline_of(by_zone: dict[str, list[outline.Polygon]]) -> list[outline.Polygon]:
    """A park's outline: the union of all its zones."""
    return geometry.union(
        [polygon for polygons in by_zone.values() for polygon in polygons]
    )


def _multipolygon(polygons: list[outline.Polygon]) -> dict[str, Any]:
    return {
        "type": "MultiPolygon",
        "coordinates": [
            [[[round(lon, 6), round(lat, 6)] for lon, lat in [*ring, ring[0]]] for ring in polygon]
            for polygon in polygons
        ],
    }


# MARK: - Prefectures


def fetch_natural_earth(version: str, *, refresh: bool) -> None:
    directory = rawstore.version_directory(NATURAL_EARTH, version)
    target = directory / PREFECTURES_FILE
    if not _wanted(target, refresh):
        return
    record = FetchRecord(source=NATURAL_EARTH_TERMS, fetched_at=rawstore.utc_now())
    path = directory / NATURAL_EARTH_ZIP
    if refresh or not path.exists():
        with client() as session:
            _download(session, NATURAL_EARTH_URL, path, record)
    features = [
        {
            "type": "Feature",
            "properties": {
                key: feature.attributes.get(key)
                for key in ("iso_3166_2", "name", "name_local", "name_ja", "type_en")
            },
            "geometry": _multipolygon(feature.polygons),
        }
        for feature in shapefile.read_zip(path)
        if feature.attributes.get("adm0_a3") == "JPN"
        and str(feature.attributes.get("iso_3166_2") or "").startswith("JP-")
    ]
    with zipfile.ZipFile(path) as archive:
        names = [name for name in archive.namelist() if name.endswith("VERSION.txt")]
        version_text = archive.read(names[0]).decode().strip() if names else "unknown"
    target.write_text(json.dumps(
        {"type": "FeatureCollection", "version": version_text, "features": features},
        ensure_ascii=False,
    ))
    record.add_file(target, root=directory, note=f"Natural Earth {version_text}, Japan only")
    _record_write(record, directory)
    print(f"    {NATURAL_EARTH}: {len(features)} prefectures (Natural Earth {version_text})")


# MARK: - Ministry pages and statistics


def fetch_moe(version: str, *, refresh: bool) -> list[moe.QuasiPark]:
    directory = rawstore.version_directory(MOE, version)
    record = FetchRecord(source=MOE_TERMS, fetched_at=rawstore.utc_now())
    files = {
        "quasi-national-parks.html": moe.QUASI_LIST_URL,
        "offices.html": moe.OFFICE_URL,
        "naturalpark_04.xlsx": moe.VISITORS_URL,
        "naturalpark_08.xlsx": moe.VISITOR_CENTRES_URL,
    }
    with client() as session:
        for name, url in files.items():
            path = directory / name
            if _wanted(path, refresh):
                headers = _download(session, url, path, record)
                print(f"    {MOE}: {name} (Last-Modified {headers.get('last-modified')})")
    _record_write(record, directory)
    parks = moe.quasi_parks((directory / "quasi-national-parks.html").read_text())
    print(f"    {MOE}: {len(parks)} quasi-national parks on the Ministry's list")
    return parks


# MARK: - Wikidata, Wikipedia and Commons


SPARQL = f"""
SELECT ?item ?class ?ja ?en ?article ?image ?commons ?coord ?inception ?area WHERE {{
  VALUES ?class {{ wd:{NATIONAL_PARK_CLASS} wd:{QUASI_NATIONAL_PARK_CLASS} }}
  ?item wdt:P31 ?class .
  OPTIONAL {{ ?item rdfs:label ?ja FILTER(LANG(?ja) = "ja") }}
  OPTIONAL {{ ?item rdfs:label ?en FILTER(LANG(?en) = "en") }}
  OPTIONAL {{ ?article schema:about ?item ;
             schema:isPartOf <https://en.wikipedia.org/> }}
  OPTIONAL {{ ?item wdt:P18 ?image }}
  OPTIONAL {{ ?item wdt:P373 ?commons }}
  OPTIONAL {{ ?item wdt:P625 ?coord }}
  OPTIONAL {{ ?item wdt:P571 ?inception }}
  OPTIONAL {{ ?item p:P2046/psn:P2046/wikibase:quantityAmount ?area }}
}}
"""


def fetch_wikidata(version: str, *, refresh: bool) -> dict[str, dict[str, Any]]:
    """Japanese label → the park's Wikidata item, flattened (see ``wikidata_items``)."""
    directory = rawstore.version_directory(WIKIDATA, version)
    path = directory / WIKIDATA_FILE
    if _wanted(path, refresh):
        record = FetchRecord(source=WIKIDATA_TERMS, fetched_at=rawstore.utc_now())
        with client() as session:
            response = http.get(
                session, WIKIDATA_SPARQL, params={"query": SPARQL, "format": "json"},
                expect="application/sparql-results+json",
            )
        record.add_request(WIKIDATA_SPARQL, {"query": SPARQL})
        path.write_text(json.dumps(response.json(), ensure_ascii=False, indent=1))
        record.add_file(path, root=directory)
        _record_write(record, directory)
    items = wikidata_items(json.loads(path.read_text()))
    print(f"    {WIKIDATA}: {len(items)} park items")
    return items


def wikidata_items(payload: dict[str, Any]) -> dict[str, dict[str, Any]]:
    """SPARQL rows, one per item and label: ``{"qid", "class", "en", "article",
    "image", "commons", "coordinate": (lat, lon), "inception", "areaHectares"}`` by
    Japanese label. Where an item has two values of a property, the first in the response
    is kept. The area is Wikidata's, normalised to square metres, given in hectares."""
    items: dict[str, dict[str, Any]] = {}
    for row in payload.get("results", {}).get("bindings", []):
        def value(key: str, row: dict[str, Any] = row) -> str | None:
            return (row.get(key) or {}).get("value")

        label = value("ja")
        if not label:
            continue
        item = items.setdefault(label, {
            "qid": (value("item") or "").rsplit("/", 1)[-1],
            "class": (value("class") or "").rsplit("/", 1)[-1],
        })
        for key in ("en", "article", "image", "commons", "inception"):
            if item.get(key) is None and value(key):
                item[key] = value(key)
        if item.get("areaHectares") is None and (area := value("area")):
            item["areaHectares"] = float(area) / 10_000
        if item.get("coordinate") is None and (point := value("coord")):
            longitude, latitude = point.removeprefix("Point(").rstrip(")").split()
            item["coordinate"] = (float(latitude), float(longitude))
    return items


def fetch_wikipedia(
    version: str,
    quasi: list[moe.QuasiPark],
    items: dict[str, dict[str, Any]],
    *,
    refresh: bool,
) -> None:
    directory = rawstore.version_directory(WIKIPEDIA, version)
    path = directory / SUMMARIES_FILE
    if not _wanted(path, refresh):
        return
    record = FetchRecord(source=WIKIPEDIA_TERMS, fetched_at=rawstore.utc_now())
    summaries: dict[str, Any] = {}
    with client() as session:
        for park in quasi:
            article = (items.get(park.name) or {}).get("article")
            if not article:
                continue
            title = article.rsplit("/wiki/", 1)[-1]
            url = WIKI_SUMMARY + title
            try:
                response = http.get(session, url, expect="application/json")
            except http.FetchError as error:
                print(f"    {WIKIPEDIA}: {park.name} failed ({error})")
                continue
            record.add_request(url)
            summaries[park.name] = response.json()
    path.write_text(json.dumps(summaries, ensure_ascii=False, indent=1))
    record.add_file(path, root=directory)
    _record_write(record, directory)
    print(f"    {WIKIPEDIA}: {len(summaries)} quasi-national park leads")


def commons_name(reference: str) -> str:
    """A Commons file's name from a guide's ``File:…`` or a Wikidata image URL."""
    name = reference.strip()
    if "/Special:FilePath/" in name:
        name = httpx.URL(name).path.rsplit("/", 1)[-1]
    name = name.removeprefix("File:").removeprefix("file:")
    return name.replace("_", " ").strip()


def photo_path(directory: Path, name: str) -> Path:
    """Where a Commons photograph is kept in the raw store, by its file name."""
    return directory / "photos" / photo_filename(f"https://commons.wikimedia.org/wiki/File:{quote(name)}")


def fetch_commons(
    version: str,
    parks: list[dict[str, Any]],
    quasi: list[moe.QuasiPark],
    items: dict[str, dict[str, Any]],
    *,
    refresh: bool,
) -> None:
    """Licence metadata for every guide photograph and every park's Wikidata image, and
    the guides' photographs at up to 1920 pixels for the build to resize."""
    directory = rawstore.version_directory(COMMONS, version)
    record = FetchRecord(source=COMMONS_TERMS, fetched_at=rawstore.utc_now())
    licences_path = directory / LICENCES_FILE
    licences: dict[str, Any] = (
        json.loads(licences_path.read_text()) if licences_path.exists() and not refresh else {}
    )
    guide_files = [
        commons_name(photo["file"])
        for park in parks
        for photo in (content.guide(park["id"]) or {}).get("photos") or []
        if photo.get("file")
    ]
    wikidata_files = [
        commons_name(item["image"])
        for item in items.values()
        if item.get("image")
    ]
    wanted = list(dict.fromkeys([*guide_files, *wikidata_files]))
    downloaded = 0
    with client() as session:
        for name in wanted:
            if name not in licences:
                meta = commons_licence(session, COMMONS_FILE_PATH + quote(name), record)
                if meta is not None:
                    licences[name] = meta
            if name not in guide_files:
                continue
            path = photo_path(directory, name)
            if path.exists() and not refresh:
                continue
            if not refresh and (earlier := _earlier_copy(path, version)):
                path.parent.mkdir(parents=True, exist_ok=True)
                path.hardlink_to(earlier)
                continue
            url = f"{COMMONS_FILE_PATH}{quote(name)}?width={PHOTO_WIDTH}"
            try:
                _download(session, url, path, record, note=name)
                downloaded += 1
            except (http.FetchError, httpx.HTTPError) as error:
                print(f"    {COMMONS}: {name} failed ({error})")
    licences_path.write_text(json.dumps(licences, ensure_ascii=False, indent=1))
    record.add_file(licences_path, root=directory)
    _record_write(record, directory)
    print(
        f"    {COMMONS}: {len(licences)} licences ({len(guide_files)} guide photographs, "
        f"{len(wikidata_files)} Wikidata images), {downloaded} photographs downloaded"
    )


def _earlier_copy(path: Path, version: str) -> Path | None:
    """The same raw file in an older snapshot: a Commons file name names its bytes."""
    relative = path.relative_to(config.RAW_DIR / version)
    for older in rawstore.versions(COMMONS):
        if older < version and (candidate := config.RAW_DIR / older / relative).exists():
            return candidate
    return None


# MARK: - OpenStreetMap


QUASI_QUERY = """[out:json][timeout:900];
area["ISO3166-1"="JP"]["admin_level"="2"]->.jp;
(
  relation["name"~"国定公園"](area.jp);
  way["name"~"国定公園"](area.jp);
  {wikidata}
);
out geom;
"""

RAIL_QUERY = """[out:json][timeout:900];
relation["route"="train"]({s:.4f},{w:.4f},{n:.4f},{e:.4f})->.routes;
.routes out body;
relation(br.routes)["type"="route_master"];
out body;
way(r.routes)["railway"];
out geom qt;
node(r.routes);
out qt;
"""

PARK_QUERY = """[out:json][timeout:600];
nwr["tourism"~"^(alpine_hut|wilderness_hut)$"]({s:.5f},{w:.5f},{n:.5f},{e:.5f});
out center tags;
node["railway"~"^(station|halt)$"]({S:.4f},{W:.4f},{N:.4f},{E:.4f});
out;
"""


def fetch_osm(
    version: str,
    parks: list[dict[str, Any]],
    outlines: dict[str, list[outline.Polygon]],
    quasi: list[moe.QuasiPark],
    items: dict[str, dict[str, Any]],
    *,
    refresh: bool,
) -> None:
    """Quasi-national park outlines, passenger rail by region, and per national park its
    huts and the stations within reach. One query at a time, each saved as it lands."""
    directory = rawstore.version_directory(OSM, version)
    record = FetchRecord(source=OSM_TERMS, fetched_at=rawstore.utc_now())
    path = directory / QUASI_OUTLINES_FILE
    if _wanted(path, refresh):
        qids = [
            item["qid"] for park in quasi if (item := items.get(park.name)) and item.get("qid")
        ]
        pattern = "|".join(qids)
        clauses = (
            f'relation["wikidata"~"^({pattern})$"](area.jp);\n'
            f'  way["wikidata"~"^({pattern})$"](area.jp);'
            if qids else ""
        )
        _overpass(QUASI_QUERY.format(wikidata=clauses), path, record)
    for region, (south, west, north, east) in RAIL_REGIONS.items():
        path = directory / "rail" / f"{region}.json"
        if _wanted(path, refresh):
            query = RAIL_QUERY.format(s=south, w=west, n=north, e=east)
            _overpass(query, path, record)
    for park in parks:
        path = directory / "parks" / f"{park['id']}.json"
        polygons = outlines.get(park["id"])
        if not polygons or not _wanted(path, refresh):
            continue
        south, west, north, east = outline.bbox(polygons)  # type: ignore[misc]
        pad_lat = STATION_REACH_KM / 111.0
        pad_lon = STATION_REACH_KM / (111.0 * max(0.2, _cos_deg((south + north) / 2)))
        query = PARK_QUERY.format(
            s=south, w=west, n=north, e=east,
            S=south - pad_lat, W=west - pad_lon, N=north + pad_lat, E=east + pad_lon,
        )
        _overpass(query, path, record)
    _record_write(record, directory)


def _cos_deg(degrees: float) -> float:
    return math.cos(math.radians(degrees))


# The main instance first: when it is full it says so at once (429, 504), and backing off
# gets a slot. overpass.kumi.systems and overpass.private.coffee are one server, which
# holds a busy request open for many minutes before refusing it, so it is asked once.
OVERPASS_ENDPOINTS = (
    ("https://overpass-api.de/api/interpreter",
     http.Politeness(attempts=6, backoff_seconds=30.0, timeout_seconds=600.0)),
    ("https://overpass.private.coffee/api/interpreter",
     http.Politeness(attempts=2, backoff_seconds=60.0, timeout_seconds=300.0)),
)


def _overpass_query(query: str, record: FetchRecord) -> dict[str, Any]:
    """One query against each instance in turn, each with its own patience."""
    problems = []
    for endpoint, politeness in OVERPASS_ENDPOINTS:
        try:
            with client(politeness) as patient:
                response = http.post(
                    patient, endpoint, data={"data": query}, politeness=politeness,
                    expect="application",
                )
            payload = response.json()
        except (http.FetchError, ValueError) as error:
            problems.append(f"{endpoint}: {error}")
            continue
        if "elements" in payload:
            record.add_request(endpoint, {"data": query}, elements=len(payload["elements"]))
            return payload
        problems.append(f"{endpoint}: no elements in the response")
    raise http.FetchError("; ".join(problems))


def _overpass(query: str, path: Path, record: FetchRecord) -> None:
    """Run one query, keep its answer, and pause: Overpass is volunteer-run and often
    full, so a query every endpoint turned away is tried again after a rest."""
    for round_number in range(3):
        if round_number:
            time.sleep(120 * round_number)
        try:
            payload = _overpass_query(query, record)
        except http.FetchError as error:
            problem = error
            continue
        # A query that runs out of time answers 200 with what it had so far and a remark;
        # half a railway is not an answer.
        remark = str(payload.get("remark") or "")
        if "runtime error" not in remark:
            break
        problem = http.FetchError(remark)
    else:
        print(f"    {OSM}: {path.name} failed ({problem}); run the fetch again to resume")
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False))
    record.add_file(path, root=record_root(path))
    # Recorded as each answer lands, so an interrupted fetch still says what it holds.
    _record_write(record, record_root(path))
    record.requests, record.files = [], []
    print(f"    {OSM}: {path.parent.name}/{path.name}, {len(payload['elements'])} elements",
          flush=True)
    time.sleep(10)


# MARK: - Documents


def fetch_documents(version: str, parks: list[dict[str, Any]], *, refresh: bool) -> None:
    """The brochure page and every park page, and a request to each PDF they link."""
    directory = rawstore.version_directory(DOCUMENTS, version)
    path = directory / DOCUMENTS_FILE
    if not _wanted(path, refresh):
        return
    record = FetchRecord(source=DOCUMENTS_TERMS, fetched_at=rawstore.utc_now())
    pages: dict[str, str] = {"brochures": moe.BROCHURE_URL}
    for park in parks:
        pages[park["slug"]] = moe.PARK_PAGE.format(slug=park["slug"])
    found: list[dict[str, Any]] = []
    with client() as session:
        for name, url in pages.items():
            page_path = directory / "pages" / f"{name}.html"
            if refresh or not page_path.exists():
                try:
                    response = http.get(session, url, expect="text/html")
                except http.FetchError as error:
                    print(f"    {DOCUMENTS}: {url} failed ({error})")
                    continue
                page_path.parent.mkdir(parents=True, exist_ok=True)
                page_path.write_text(response.text)
                record.add_request(url)
                record.add_file(page_path, root=directory)
            text = page_path.read_text()
            if name == "brochures":
                for entry in moe.brochures(text):
                    found.append({
                        "page": url, "park": entry.park, "title": entry.title,
                        "url": entry.url, "category": entry.category, "size": entry.size,
                    })
            else:
                for title, link in moe.pdf_links(text, url):
                    found.append({"page": url, "slug": name, "title": title, "url": link})
        for document in found:
            response = _head(session, document["url"])
            if response is None:
                document["status"] = None
                continue
            document["status"] = response.status_code
            document["contentType"] = response.headers.get("content-type")
            if length := response.headers.get("content-length"):
                document["bytes"] = int(length)
            record.add_request(document["url"], method="HEAD", status=response.status_code)
            if response.status_code == 200:
                document["isPDF"] = _is_pdf(session, document["url"], document["contentType"])
    path.write_text(json.dumps(found, ensure_ascii=False, indent=1))
    record.add_file(path, root=directory)
    _record_write(record, directory)
    usable = sum(1 for document in found if document.get("status") == 200)
    print(f"    {DOCUMENTS}: {len(found)} documents linked, {usable} answer 200")


def _is_pdf(session: httpx.Client, url: str, content_type: str | None) -> bool:
    """Whether a document opens as a PDF. One brochure is served as
    ``application/illustrator``, which is a PDF inside when saved with PDF compatibility:
    its first bytes say which."""
    if content_type and "pdf" in content_type:
        return True
    try:
        response = session.get(url, headers={"Range": "bytes=0-1023"})
    except httpx.HTTPError:
        return False
    time.sleep(http.DEFAULT_POLITENESS.pause_seconds)
    return response.status_code in (200, 206) and b"%PDF-" in response.content[:1024]
