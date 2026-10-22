"""A Wikipedia lead paragraph for places whose own sources publish no prose.

Forests, grasslands, refuges, BLM lands, natural landmarks, byways and most state parks
arrive from their agencies as a name, a boundary and an area. Wikipedia usually has an
article, and its lead says what the place is. Used only when it is verifiably the same
place, because a summary of the wrong place is a false fact delivered with confidence
(``AGENTS.md`` §4):

1. **Title.** The article reached by one of the place's own names — "<name>
   <designation>", then with the state appended the way Wikipedia disambiguates — and,
   after redirects, still titled with the place's name. Disambiguation pages never count.
2. **Location.** The article's coordinates fall inside the place's outline, or within
   ``NEAR_KM`` of it, or of the point or route a place without an outline has.

An article that fails either test is not used, and the build writes every rejection to
``work/wikipedia-report.json`` so a near miss can be curated by hand. The text keeps its
licence (CC BY-SA 4.0) and its link, and the app credits both beneath it.

Fetching is batched through the MediaWiki action API — twenty titles a request — and
cached per title in ``raw/<date>/wikipedia-places/``, so a rebuild reads the cache and
never the network.
"""

from __future__ import annotations

import json
import math
import re
from collections.abc import Iterable
from pathlib import Path
from typing import Any

from . import config, ids, outline, rawstore
from .rawstore import FetchRecord, SourceTerms
from .sources import http

API = "https://en.wikipedia.org/w/api.php"
COMMONS_API = "https://commons.wikimedia.org/w/api.php"
SOURCE = "wikipedia-places"
PAGES_FILE = "pages.json"
IMAGES_FILE = "images.json"
LICENCE = "CC BY-SA 4.0"
BATCH = 20

# How far an article's coordinates may lie from a place's outline, point or route.
NEAR_KM = 10.0
# The longest lead the app shows, in sentences and characters.
MAX_SENTENCES = 3
MAX_CHARACTERS = 620

TERMS = SourceTerms(
    identifier="wikipedia-places",
    title="Wikipedia lead paragraphs and page images for places without agency prose",
    url=API,
    licence="Text CC BY-SA 4.0; images under their own Commons licences",
    attribution="Summaries: Wikipedia, CC BY-SA 4.0, linked from each place",
    notes="Used only where the article's title and coordinates both match the place.",
)

# Kinds whose sources publish no prose, and which a Wikipedia lead can describe.
KINDS = frozenset({
    "statePark", "nationalForest", "nationalGrassland", "wildlifeRefuge", "blmMonument",
    "blmConservationArea", "naturalLandmark", "scenicByway",
})

STATE_NAMES = {
    "AL": "Alabama", "AK": "Alaska", "AS": "American Samoa", "AZ": "Arizona",
    "AR": "Arkansas", "CA": "California", "CO": "Colorado", "CT": "Connecticut",
    "DE": "Delaware", "DC": "District of Columbia", "FL": "Florida", "GA": "Georgia",
    "GU": "Guam", "HI": "Hawaii", "ID": "Idaho", "IL": "Illinois", "IN": "Indiana",
    "IA": "Iowa", "KS": "Kansas", "KY": "Kentucky", "LA": "Louisiana", "ME": "Maine",
    "MD": "Maryland", "MA": "Massachusetts", "MI": "Michigan", "MN": "Minnesota",
    "MS": "Mississippi", "MO": "Missouri", "MT": "Montana", "NE": "Nebraska", "NV": "Nevada",
    "NH": "New Hampshire", "NJ": "New Jersey", "NM": "New Mexico", "NY": "New York",
    "NC": "North Carolina", "ND": "North Dakota", "MP": "Northern Mariana Islands",
    "OH": "Ohio", "OK": "Oklahoma", "OR": "Oregon", "PA": "Pennsylvania",
    "PR": "Puerto Rico", "RI": "Rhode Island", "SC": "South Carolina", "SD": "South Dakota",
    "TN": "Tennessee", "TX": "Texas", "UT": "Utah", "VT": "Vermont", "VI": "U.S. Virgin Islands",
    "VA": "Virginia", "WA": "Washington", "WV": "West Virginia", "WI": "Wisconsin",
    "WY": "Wyoming",
}

# Words that already say a byway is a road, so "Scenic Byway" is not appended to them.
_ROAD_WORDS = re.compile(
    r"\b(byway|road|highway|parkway|route|trail|drive|loop|way|pass|corridor)\b", re.I
)


def wants(place: dict[str, Any]) -> bool:
    """Whether a place is one this module may describe."""
    return place["kind"] in KINDS and not place.get("summary")


def candidate_titles(place: dict[str, Any]) -> list[str]:
    """The titles an article about this place would most likely carry, best first."""
    name, designation, kind = place["name"], place.get("designation") or "", place["kind"]
    state = STATE_NAMES.get((place.get("states") or [""])[0])
    titles: list[str] = []
    if kind in ("naturalLandmark", "scenicByway"):
        titles.append(name)
        if kind == "scenicByway" and not _ROAD_WORDS.search(name):
            titles.append(f"{name} Scenic Byway")
        if state:
            titles.append(f"{name} ({state})")
    else:
        full = f"{name} {designation}".strip()
        titles.append(full)
        if state:
            titles.append(f"{full} ({state})")
    return list(dict.fromkeys(titles))


# MARK: - Fetching


def fetch(places: Iterable[dict[str, Any]], version: str, *, refresh: bool = False) -> Path:
    """Every candidate title's page into the cache, then every page image's licence."""
    directory = rawstore.version_directory(SOURCE, version)
    pages_path, images_path = directory / PAGES_FILE, directory / IMAGES_FILE
    pages: dict[str, Any] = (
        json.loads(pages_path.read_text()) if pages_path.exists() and not refresh else {}
    )
    images: dict[str, Any] = (
        json.loads(images_path.read_text()) if images_path.exists() and not refresh else {}
    )
    titles = [
        title
        for place in places
        if wants(place)
        for title in candidate_titles(place)
        if title not in pages
    ]
    record = FetchRecord(source=TERMS, fetched_at=rawstore.utc_now())
    with http.client() as session:
        for start in range(0, len(titles), BATCH):
            batch = titles[start : start + BATCH]
            pages.update(_query_pages(session, batch, record))
            if start // BATCH % 10 == 0:
                print(f"    wikipedia: {start + len(batch)} of {len(titles)} titles", flush=True)
                pages_path.write_text(json.dumps(pages, ensure_ascii=False))
        files = sorted({
            page["image"] for page in pages.values()
            if page and page.get("image") and page["image"] not in images
        })
        for start in range(0, len(files), 50):
            images.update(_query_images(session, files[start : start + 50], record))
    pages_path.write_text(json.dumps(pages, ensure_ascii=False))
    images_path.write_text(json.dumps(images, ensure_ascii=False))
    record.add_file(pages_path, root=directory)
    record.add_file(images_path, root=directory)
    record.write(directory)
    found = sum(1 for page in pages.values() if page)
    print(f"    wikipedia: {found} of {len(pages)} titles have an article")
    return directory


def _query_pages(session: Any, titles: list[str], record: FetchRecord) -> dict[str, Any]:
    parameters = {
        "action": "query",
        "format": "json",
        "formatversion": "2",
        "redirects": "1",
        "titles": "|".join(titles),
        "prop": "extracts|coordinates|pageprops|pageimages|info",
        "exintro": "1",
        "explaintext": "1",
        "exlimit": "max",
        "colimit": "max",
        "coprimary": "primary",
        "ppprop": "disambiguation",
        "piprop": "name",
        "inprop": "url",
    }
    try:
        response = http.get(session, API, params=parameters, expect="application/json")
    except http.FetchError as error:
        print(f"    wikipedia: batch failed ({error}); left for the next run")
        return {}
    record.add_request(API, {"titles": len(titles)})
    query = response.json().get("query") or {}
    # The answer is by resolved title; walk normalisation and redirects back to what was
    # asked, so each requested title caches its own result.
    resolved = {title: title for title in titles}
    for step in ("normalized", "redirects"):
        mapping = {entry["from"]: entry["to"] for entry in query.get(step) or []}
        resolved = {asked: mapping.get(now, now) for asked, now in resolved.items()}
    by_title = {page.get("title"): page for page in query.get("pages") or []}
    result: dict[str, Any] = {}
    for asked, final in resolved.items():
        page = by_title.get(final)
        if not page or page.get("missing") or page.get("invalid"):
            result[asked] = None
            continue
        coordinates = (page.get("coordinates") or [{}])[0]
        result[asked] = {
            "title": page.get("title"),
            "extract": page.get("extract") or "",
            "url": page.get("fullurl"),
            "disambiguation": "disambiguation" in (page.get("pageprops") or {}),
            "latitude": coordinates.get("lat"),
            "longitude": coordinates.get("lon"),
            "image": page.get("pageimage"),
        }
    return result


def _query_images(session: Any, files: list[str], record: FetchRecord) -> dict[str, Any]:
    parameters = {
        "action": "query",
        "format": "json",
        "formatversion": "2",
        "titles": "|".join(f"File:{name}" for name in files),
        "prop": "imageinfo",
        "iiprop": "extmetadata|url",
        "iiurlwidth": "1280",
    }
    try:
        response = http.get(session, COMMONS_API, params=parameters, expect="application/json")
    except http.FetchError as error:
        print(f"    wikipedia: image batch failed ({error})")
        return {}
    record.add_request(COMMONS_API, {"files": len(files)})
    result: dict[str, Any] = {}
    for page in (response.json().get("query") or {}).get("pages") or []:
        name = (page.get("title") or "").removeprefix("File:").replace(" ", "_")
        for info in page.get("imageinfo") or []:
            meta = info.get("extmetadata") or {}
            result[name] = {
                "licence": (meta.get("LicenseShortName") or {}).get("value"),
                "artist": (meta.get("Artist") or {}).get("value"),
                "thumbURL": info.get("thumburl"),
                "descriptionURL": info.get("descriptionurl"),
            }
    # Commons answers with spaces; the page image name has underscores. Keep both forms.
    for name in files:
        if name not in result and name.replace(" ", "_") in result:
            result[name] = result[name.replace(" ", "_")]
    return result


# MARK: - Matching


def enrich(
    places: list[dict[str, Any]],
    boundaries: dict[str, Any],
    routes: dict[str, Any],
    cache: Path | None,
    image_for: Any,
) -> dict[str, int]:
    """Give each eligible place a verified lead paragraph, in place. ``image_for`` turns a
    Commons licence record into the app's image entry, or ``None`` if it is not reusable.

    Returns counts, and writes the rejections to ``work/wikipedia-report.json``.
    """
    if cache is None:
        return {}
    pages = json.loads((cache / PAGES_FILE).read_text())
    images_path = cache / IMAGES_FILE
    images = json.loads(images_path.read_text()) if images_path.exists() else {}
    counts = {"matched": 0, "noArticle": 0, "rejected": 0}
    report: list[dict[str, Any]] = []
    for place in places:
        if not wants(place):
            continue
        decision = _match(place, pages, boundaries.get(place["id"]), routes.get(place["id"]))
        if isinstance(decision, str):
            counts["rejected" if decision != "no article" else "noArticle"] += 1
            if decision != "no article":
                report.append({"id": place["id"], "name": place["name"], "reason": decision})
            continue
        counts["matched"] += 1
        place["summary"] = lead(decision["extract"])
        place["summarySource"] = "Wikipedia"
        place["summaryLicence"] = LICENCE
        place["summaryURL"] = decision["url"]
        if not place.get("infoURL") and not place.get("officialURL"):
            place["infoURL"] = decision["url"]
        if not place.get("image") and decision.get("image"):
            licence = images.get(decision["image"]) or images.get(
                decision["image"].replace(" ", "_")
            )
            if image := image_for(licence):
                place["image"] = image
    path = config.WORK_DIR / "wikipedia-report.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, ensure_ascii=False, indent=1) + "\n")
    print(
        f"    wikipedia: {counts['matched']} summaries; {counts['rejected']} articles "
        f"rejected ({path.relative_to(config.PIPELINE_ROOT)}); {counts['noArticle']} none"
    )
    return counts


def _match(
    place: dict[str, Any],
    pages: dict[str, Any],
    boundary: dict[str, Any] | None,
    route: dict[str, Any] | None,
) -> dict[str, Any] | str:
    """The verified page for a place, or why there is none."""
    reasons: list[str] = []
    for title in candidate_titles(place):
        page = pages.get(title)
        if not page:
            continue
        if page.get("disambiguation"):
            reasons.append(f"{title}: disambiguation page")
            continue
        if not page.get("extract"):
            reasons.append(f"{title}: no lead text")
            continue
        if not _title_names_place(page.get("title") or "", place["name"]):
            reasons.append(f"{title}: resolved to {page.get('title')!r}")
            continue
        latitude, longitude = page.get("latitude"), page.get("longitude")
        if latitude is None or longitude is None:
            reasons.append(f"{title}: article has no coordinates to check")
            continue
        distance = _distance_to_place(latitude, longitude, place, boundary, route)
        if distance > NEAR_KM:
            reasons.append(f"{title}: article placed {distance:.0f} km away")
            continue
        return page
    return "; ".join(reasons) if reasons else "no article"


def _title_names_place(title: str, name: str) -> bool:
    """Whether a resolved article title still names the place, parenthetical aside."""
    bare = re.sub(r"\s*\([^)]*\)\s*$", "", title)
    return ids.slug(name) in ids.slug(bare)


def _distance_to_place(
    latitude: float,
    longitude: float,
    place: dict[str, Any],
    boundary: dict[str, Any] | None,
    route: dict[str, Any] | None,
) -> float:
    """Kilometres from a point to a place: zero inside its outline, else to its nearest
    outline vertex, route vertex or centre."""
    candidates: list[tuple[float, float]] = []
    if boundary:
        polygons = [[outline.decode(ring) for ring in polygon] for polygon in boundary["polygons"]]
        if outline.contains(polygons, longitude, latitude):
            return 0.0
        candidates.extend(point for polygon in polygons for ring in polygon for point in ring)
    if route:
        for path in route.get("paths") or []:
            candidates.extend(outline.decode(path) if isinstance(path, str) else path)
    centre = place.get("centre") or {}
    if centre:
        candidates.append((centre["longitude"], centre["latitude"]))
    return min(
        (_haversine_km(latitude, longitude, lat, lon) for lon, lat in candidates),
        default=math.inf,
    )


def _haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi, dlambda = phi2 - phi1, math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2
    return 6371.0 * 2 * math.asin(math.sqrt(a))


def lead(extract: str) -> str:
    """The first sentences of a lead, short enough for a map card."""
    text = re.sub(r"\s+", " ", extract).strip()
    # Pronunciation and native-name parentheticals add nothing on a card.
    text = re.sub(r"\s*\((?:[^()]*?(?:/|listen|pronounced|IPA)[^()]*?)\)", "", text)
    sentences = re.split(r"(?<=[.!?])\s+(?=[A-Z0-9“\"])", text)
    chosen: list[str] = []
    for sentence in sentences:
        if chosen and (
            len(chosen) == MAX_SENTENCES or len(" ".join([*chosen, sentence])) > MAX_CHARACTERS
        ):
            break
        chosen.append(sentence)
    return " ".join(chosen).strip()
