"""Fetching for the bundled reference dataset — the half of ``fetch`` the app's map,
guides and overviews read, as opposed to the offline packs.

Everything lands in the date-versioned raw store like the pack sources do, with a
``source.json`` recording what was asked for and under which terms:

``nps-api/``
    The NPS Data API's parks, visitor centres, passport stamp locations, places and
    campgrounds. Needs ``NPS_API_KEY``.
``unit-boundaries/``
    Every NPS unit's outline from the Land Resources Division service, generalised to
    about 50 m — fine enough for a park outline at any zoom the map draws outlines at.
``padus/``
    The state parks and other agencies' sites curated in ``content/``, from PAD-US.
``wikipedia/``
    Lead summaries and lead-image licence metadata for those same curated sites, which
    have no NPS record. Research material and image credits; no text is copied out of it.
``federal-lands/``, ``transport/``
    Every other public land the map outlines, and its road and rail layers
    (``lands_fetch``).
``trails-national/``, ``trail-elevation/``
    Every national park's trail segments and 3DEP samples along them
    (``trail_catalogue``).
``brochures/``, ``climate/``
    Each NPS unit's brochure links (``brochures``) and each national park's monthly
    climate (``climate``).
``photos/``
    The NPS-credited photographs chosen for each national park's guide, at full size, so
    the build can resize them without fetching again.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any
from urllib.parse import quote

import httpx

from . import brochures, climate, config, lands_fetch, rawstore, reference_content, trail_catalogue
from .rawstore import FetchRecord, SourceTerms
from .sources import arcgis, http, npsapi

PADUS_LAYER = (
    "https://services.arcgis.com/v01gqwM5QqNysAAi/ArcGIS/rest/services/Fee_Manager/"
    "FeatureServer/0"
)
PADUS_MANAGEMENT_LAYER = (
    "https://services.arcgis.com/v01gqwM5QqNysAAi/ArcGIS/rest/services/PADUS_Management_Areas/"
    "FeatureServer/0"
)
PADUS_FIELDS = "Unit_Nm,Mang_Name,Mang_Type,Des_Tp,State_Nm,GIS_Acres,FeatClass"
# The management-areas layer is PAD-US 4.1, cut by region and ecoregion, and names its
# area field differently.
PADUS_MANAGEMENT_FIELDS = "Unit_Nm,Mang_Name,Mang_Type,Des_Tp,State_Nm,GIS_AcreD,FeatClass"

PADUS_TERMS = SourceTerms(
    identifier="padus",
    title="Protected Areas Database of the United States (PAD-US), fee-manager layer",
    url=PADUS_LAYER,
    licence="USGS data release, public domain",
    attribution="Boundaries: USGS Gap Analysis Project, PAD-US",
    notes="Only the state parks and federal sites curated in Pipeline/content are asked for.",
)

UNIT_BOUNDARY_TERMS = SourceTerms(
    identifier="nps-unit-boundaries",
    title="NPS Land Resources Division boundaries, every unit",
    url=arcgis.BOUNDARY_LAYER,
    licence="Public NPS dataset",
    attribution="Boundaries: National Park Service, Land Resources Division",
    notes="Generalised by the server to about 50 m for the map's outlines.",
)

WIKIPEDIA_TERMS = SourceTerms(
    identifier="wikipedia",
    title="Wikipedia page summaries and Wikimedia Commons image metadata",
    url="https://en.wikipedia.org/api/rest_v1/",
    licence="Text CC BY-SA 4.0 (used for research, not copied); images under their own licences",
    attribution="Photographs credited individually, via Wikimedia Commons",
    notes=(
        "Only lead images under a licence that allows reuse with credit are kept, and the "
        "credit and licence travel with the image into the app."
    ),
)

PHOTO_TERMS = SourceTerms(
    identifier="nps-photos",
    title="NPS photographs from the NPS Data API",
    url=npsapi.BASE_URL,
    licence="Public domain where credited to the NPS",
    attribution="Photographs: National Park Service, credited individually",
    notes="Anything not credited to the NPS is never downloaded.",
)

# Wikimedia asks API clients for a descriptive agent; the shared one already is.
WIKI_SUMMARY = "https://en.wikipedia.org/api/rest_v1/page/summary/"
COMMONS_API = "https://commons.wikimedia.org/w/api.php"


def fetch(*, refresh: bool = False) -> Path:
    """Fetch everything the reference build reads into ``raw/<today>/``. Returns the
    version directory."""
    version = rawstore.today()
    root = config.RAW_DIR / version
    settings = config.Settings.from_environment()

    def needed(name: str, *files: str) -> bool:
        directory = root / name
        if not refresh and all((directory / file).exists() for file in files):
            print(f"    {name}: already fetched today, leaving it alone (--refresh to redo)")
            return False
        return True

    missing = [
        name
        for name in npsapi.ENDPOINTS
        if refresh or not (root / "nps-api" / f"{name}.json").exists()
    ]
    if missing:
        _fetch_nps_api(settings.require_nps_key(), version, missing)
    else:
        print("    nps-api: already fetched today, leaving it alone (--refresh to redo)")

    if needed("unit-boundaries", "nps-units.geojson"):
        _fetch_unit_boundaries(version)

    if needed("padus", "curated.geojson"):
        _fetch_padus(version)

    if needed("wikipedia", "summaries.json"):
        _fetch_wikipedia(version)

    if needed("federal-lands", *lands_fetch.LANDS_FILES):
        lands_fetch.fetch_lands(version)

    if needed("transport", *lands_fetch.TRANSPORT_FILES):
        lands_fetch.fetch_transport(version)

    # Each of these resumes where it left off and skips what it already holds. The build
    # module is imported here because it imports this one.
    from . import reference_build

    trails_dir = trail_catalogue.fetch(version, refresh=refresh)
    outlines = reference_build._unit_outlines(root / "unit-boundaries")
    trail_catalogue.sample_elevations(trails_dir, outlines)
    places = json.loads((reference_build.OUT / "places.json").read_text())
    codes = sorted({place["npsParkCode"] for place in places if place.get("npsParkCode")})
    brochures.fetch(codes, version, refresh=refresh)
    climate.fetch(version, refresh=refresh)

    _fetch_photos(version, refresh=refresh)
    return root


# MARK: - NPS API


def _fetch_nps_api(api_key: str, version: str, endpoints: list[str]) -> None:
    directory = rawstore.version_directory("nps-api", version)
    record = FetchRecord(source=SourceTerms(**npsapi.TERMS), fetched_at=rawstore.utc_now())
    codes = sorted({
        reference_content.api_code(row) for _, row in reference_content.national_park_rows()
    })
    with npsapi.keyed_client(api_key) as session:
        for endpoint in endpoints:
            # Parks, visitor centres and stamp locations for every unit — the map and the
            # passport cover them all. Places and campgrounds only for national parks,
            # which are the only units with a full guide.
            scoped = endpoint in {"places", "campgrounds"}
            rows = npsapi.fetch_all(
                session, endpoint, park_codes=codes if scoped else None, record=record
            )
            path = directory / f"{endpoint}.json"
            path.write_text(json.dumps(rows, ensure_ascii=False))
            record.add_file(path, root=directory)
            print(f"    nps-api/{endpoint}: {len(rows)} rows", flush=True)
    _merge_record(record, directory)


def _merge_record(record: FetchRecord, directory: Path) -> None:
    """Write ``source.json``, keeping the requests and files of an earlier partial fetch
    made the same day, so a resumed fetch still records everything it holds."""
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


# MARK: - Boundaries


def _fetch_unit_boundaries(version: str) -> None:
    directory = rawstore.version_directory("unit-boundaries", version)
    record = FetchRecord(source=UNIT_BOUNDARY_TERMS, fetched_at=rawstore.utc_now())
    with http.client() as session:
        features = arcgis.query_features(
            session,
            arcgis.BOUNDARY_LAYER,
            where="1=1",
            out_fields=arcgis.BOUNDARY_FIELDS,
            record=record,
            max_allowable_offset=0.0005,
            page_size=200,
        )
    path = directory / "nps-units.geojson"
    path.write_text(json.dumps({"type": "FeatureCollection", "features": features}))
    record.add_file(path, root=directory)
    record.write(directory)
    print(f"    unit-boundaries: {len(features)} features")


def _fetch_padus(version: str) -> None:
    """Each curated site's outline, tagged with the site's id.

    State parks come from the fee-manager layer, matched by name within the park's state:
    a state park is land the state owns. Monuments, conservation areas and refuges are
    designations laid over other ownership, so they come from the management-areas layer,
    by name in any state — Grand Staircase-Escalante crosses into Arizona.
    """
    directory = rawstore.version_directory("padus", version)
    record = FetchRecord(source=PADUS_TERMS, fetched_at=rawstore.utc_now())
    features: list[dict[str, Any]] = []
    with http.client() as session:
        for site in reference_content.curated_sites():
            names = " OR ".join(
                "Unit_Nm LIKE '{}'".format(name.replace("'", "''")) for name in site["padus"]
            )
            offset: float | None = 0.0005
            if site["kind"] == "statePark":
                layer, fields = PADUS_LAYER, PADUS_FIELDS
                where = f"({names}) AND State_Nm = '{site['states'][0]}'"
            elif site["kind"] == "wildlifeRefuge":
                # A refuge is land the Fish and Wildlife Service owns.
                layer, fields = PADUS_LAYER, PADUS_FIELDS
                where = f"({names}) AND Mang_Name = 'FWS'"
            else:
                layer, fields = PADUS_MANAGEMENT_LAYER, PADUS_MANAGEMENT_FIELDS
                where = f"({names}) AND FeatClass IN ('Designation', 'Proclamation')"
                # This layer answers a generalisation request with null geometry, so it is
                # asked for full detail and generalised here instead.
                offset = None
            found = arcgis.query_features(
                session,
                layer,
                where=where,
                out_fields=fields,
                record=record,
                max_allowable_offset=offset,
                page_size=100,
            )
            if site["kind"] != "statePark":
                # A designation and its proclamation boundary describe the same place;
                # keep the designation where both exist, so it is not drawn twice.
                classes = {(f.get("properties") or {}).get("FeatClass") for f in found}
                if "Designation" in classes:
                    found = [
                        f for f in found
                        if (f.get("properties") or {}).get("FeatClass") == "Designation"
                    ]
            for feature in found:
                feature.setdefault("properties", {})["_site"] = site["id"]
            features.extend(found)
            if not found:
                print(f"    padus: nothing found for {site['id']} ({site['padus']})")
    path = directory / "curated.geojson"
    path.write_text(json.dumps({"type": "FeatureCollection", "features": features}))
    record.add_file(path, root=directory)
    record.write(directory)
    sites = {(f.get("properties") or {}).get("_site") for f in features}
    print(f"    padus: {len(features)} features for {len(sites)} sites")


# MARK: - Wikipedia


def _fetch_wikipedia(version: str) -> None:
    directory = rawstore.version_directory("wikipedia", version)
    record = FetchRecord(source=WIKIPEDIA_TERMS, fetched_at=rawstore.utc_now())
    summaries: dict[str, Any] = {}
    with http.client() as session:
        for site in reference_content.curated_sites():
            title = site["wikipedia"]
            try:
                response = http.get(
                    session, WIKI_SUMMARY + quote(title.replace(" ", "_"), safe=""),
                    expect="application/json",
                )
            except http.FetchError as error:
                print(f"    wikipedia: {title!r} failed ({error})")
                continue
            record.add_request(WIKI_SUMMARY + title)
            summary = response.json()
            image = (summary.get("originalimage") or {}).get("source")
            summary["_licence"] = _commons_licence(session, image, record) if image else None
            summaries[site["id"]] = summary
    path = directory / "summaries.json"
    path.write_text(json.dumps(summaries, ensure_ascii=False, indent=1))
    record.add_file(path, root=directory)
    record.write(directory)
    print(f"    wikipedia: {len(summaries)} summaries")


def _commons_licence(
    session: httpx.Client, image_url: str, record: FetchRecord
) -> dict[str, Any] | None:
    """The licence and author Commons records for a lead image, or ``None``."""
    filename = image_url.rsplit("/", 1)[-1]
    # Thumbnail URLs carry a size prefix; the original's name is the last path segment
    # of the original image URL, which is what the summary hands over.
    parameters = {
        "action": "query",
        "titles": f"File:{httpx.URL(image_url).path.rsplit('/', 1)[-1]}",
        "prop": "imageinfo",
        "iiprop": "extmetadata|url",
        "iiurlwidth": "1280",
        "format": "json",
    }
    try:
        response = http.get(session, COMMONS_API, params=parameters, expect="application/json")
    except http.FetchError:
        return None
    record.add_request(COMMONS_API, parameters)
    pages = (response.json().get("query") or {}).get("pages") or {}
    for page in pages.values():
        for info in page.get("imageinfo") or []:
            meta = info.get("extmetadata") or {}
            return {
                "file": filename,
                "licence": (meta.get("LicenseShortName") or {}).get("value"),
                "licenceURL": (meta.get("LicenseUrl") or {}).get("value"),
                "artist": (meta.get("Artist") or {}).get("value"),
                "credit": (meta.get("Credit") or {}).get("value"),
                "thumbURL": info.get("thumburl"),
                "descriptionURL": info.get("descriptionurl"),
            }
    return None


# MARK: - Photographs


def _fetch_photos(version: str, *, refresh: bool) -> None:
    """Download each national park's chosen NPS photographs, once."""
    parks_path = config.RAW_DIR / version / "nps-api" / "parks.json"
    if not parks_path.exists():
        return
    directory = rawstore.version_directory("photos", version)
    record = FetchRecord(source=PHOTO_TERMS, fetched_at=rawstore.utc_now())
    parks = {row["parkCode"].upper(): row for row in json.loads(parks_path.read_text())}
    fetched = 0
    with http.client() as session:
        for _, content_row in reference_content.national_park_rows():
            code = reference_content.api_code(content_row)
            row = parks.get(code)
            if row is None:
                continue
            chosen = reference_content.choose_photos(
                row.get("images") or [], keywords=content_row.get("photoKeywords")
            )
            override = (reference_content.guide(content_row["id"]) or {}).get("heroOverride")
            if override:
                chosen = [override, *chosen]
            for image in chosen:
                path = directory / photo_filename(image["url"])
                if path.exists() and not refresh:
                    continue
                try:
                    response = http.get(session, image["url"], expect="image/")
                except http.FetchError as error:
                    print(f"    photos: {code} {image['url']} failed ({error})")
                    continue
                path.write_bytes(response.content)
                record.add_file(path, root=directory, note=f"{code}: {image['credit']}")
                fetched += 1
    if fetched:
        record.write(directory)
    print(f"    photos: {fetched} downloaded")


def photo_filename(url: str) -> str:
    """A stable local name for a remote photograph."""
    digest = hashlib.sha1(url.encode()).hexdigest()[:16]
    suffix = Path(httpx.URL(url).path).suffix.lower() or ".jpg"
    return f"{digest}{suffix}"
