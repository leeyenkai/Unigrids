"""What every country's assembly shares: outlines, coordinates, photographs, text
cleaning, the raw store and time zones.

Nothing here knows which country it is working for. A rule that does — an NPS fee
format, a notice regex written for English NPS prose — belongs in that country's package.
"""

from __future__ import annotations

import hashlib
import html
import re
import subprocess
from pathlib import Path
from typing import Any

import httpx
from timezonefinder import TimezoneFinder

from .. import config, outline, reference_content
from ..rawstore import FetchRecord
from ..sources import http

# How far each tier's outlines are generalised, in degrees (about 60 m and 110 m). The
# national parks are drawn closest and most often; everything else is a regional outline.
NATIONAL_PARK_TOLERANCE = 0.0006
OTHER_TOLERANCE = 0.0011

# Hero and gallery photographs: long edge in pixels and JPEG quality. Sized for a full-width
# iPad panel at the hero and a half-width one in the gallery. `sips` reads quality as
# a percentage on its own curve: 40 is visually clean here and about half the bytes of 68.
HERO_SIZE, HERO_QUALITY = 1600, 42
GALLERY_SIZE, GALLERY_QUALITY = 1100, 40
GALLERY_COUNT = 3

COMMONS_API = "https://commons.wikimedia.org/w/api.php"


# MARK: - Outlines and coordinates


def encode_outline(
    polygons: list[outline.Polygon] | None, tolerance: float
) -> dict[str, Any] | None:
    if not polygons:
        return None
    simplified = outline.generalise(polygons, tolerance)
    box = outline.bbox(simplified)
    if not simplified or box is None:
        return None
    return {
        "bbox": [round(value, 5) for value in box],
        "polygons": [[outline.encode(ring) for ring in polygon] for polygon in simplified],
    }


def extent(box: list[float]) -> dict[str, float]:
    south, west, north, east = box
    return {"south": south, "west": west, "north": north, "east": east}


def coordinate(row: dict[str, Any] | None) -> dict[str, float] | None:
    if not row:
        return None
    latitude, longitude = number(row.get("latitude")), number(row.get("longitude"))
    if latitude is None or longitude is None or (latitude == 0 and longitude == 0):
        return None
    return {"latitude": round(latitude, 5), "longitude": round(longitude, 5)}


def number(value: Any) -> float | None:
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def assign_time_zones(places: list[dict[str, Any]]) -> None:
    """Each place's IANA time zone, at its centre.

    A visit's calendar day is the day where it happened, whatever zone the device is in
    later (the America 250 seal, the weather for the day, one visit per place per day).
    A place that straddles zones takes its centre's — Glen Canyon is Arizona's — which is
    the zone a visitor centre in the middle keeps.
    """
    finder = TimezoneFinder()
    for place in places:
        centre = place.get("centre") or {}
        if not centre:
            continue
        zone = finder.timezone_at(lng=centre["longitude"], lat=centre["latitude"])
        if zone:
            place["timeZoneID"] = zone


# MARK: - Photographs


class UnlicensedPhotographError(ValueError):
    """A photograph reached a guide without the credit or licence it must carry."""


def guide_image(image: dict[str, Any], *, asset_name: str | None = None) -> dict[str, Any]:
    """A photograph as a guide carries it: credited, and public domain only when its own
    licence says so. ``image`` is a source's record with ``credit`` and ``licence``
    (``reference_content.choose_photos`` gives NPS photographs theirs); one missing
    either fails the build rather than shipping a photograph on assumed terms."""
    credit = clean(image.get("credit"))
    licence = (image.get("licence") or "").strip()
    if not credit or not reference_content.is_reusable_licence(licence):
        raise UnlicensedPhotographError(
            f"{image.get('url')}: credit {credit!r}, licence {licence!r}; a photograph "
            "needs both, under a licence that allows reuse"
        )
    public = reference_content.is_public_domain_licence(licence)
    entry: dict[str, Any] = {"credit": credit, "isPublicDomain": public}
    if asset_name:
        entry["assetName"] = asset_name
    else:
        entry["url"] = image["url"]
    if caption := clean(image.get("title")):
        entry["caption"] = caption
    if source := image.get("sourceURL"):
        entry["sourceURL"] = source
    if alt := clean(image.get("altText")):
        entry["altText"] = alt
    if not public:
        entry["licence"] = licence
    return entry


def wikimedia_image(licence: dict[str, Any] | None) -> dict[str, Any] | None:
    if not licence or not licence.get("thumbURL"):
        return None
    name = (licence.get("licence") or "").strip()
    if not reference_content.is_reusable_licence(name):
        return None
    credit = commons_record_credit(licence)
    if credit is None:
        return None
    public = reference_content.is_public_domain_licence(name)
    image = {
        "url": licence["thumbURL"],
        "credit": credit,
        "isPublicDomain": public,
        "sourceURL": licence.get("descriptionURL"),
    }
    if not public:
        image["licence"] = name
    return image


def photo_filename(url: str) -> str:
    """A stable local name for a remote photograph."""
    digest = hashlib.sha1(url.encode()).hexdigest()[:16]
    suffix = Path(httpx.URL(url).path).suffix.lower() or ".jpg"
    return f"{digest}{suffix}"


def resize(source: Path, destination: Path, size: int, quality: int) -> bool:
    """Resize with ``sips``, which ships with macOS — the pipeline runs on the Mac that
    builds the app. A photograph ``sips`` cannot read is skipped rather than fatal."""
    result = subprocess.run(
        [
            "sips", "-Z", str(size), "-s", "format", "jpeg",
            "-s", "formatOptions", str(quality), str(source), "--out", str(destination),
        ],
        capture_output=True,
    )
    return result.returncode == 0 and destination.exists()


def commons_licence(
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
        "iiprop": "extmetadata|url|user",
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
                "uploader": info.get("user"),
                "thumbURL": info.get("thumburl"),
                "descriptionURL": info.get("descriptionurl"),
            }
    return None


# MARK: - Text


_TAG = re.compile(r"<[^>]+>")
_SPACE = re.compile(r"\s+")


def strip_tags(text: str) -> str:
    return _SPACE.sub(" ", html.unescape(_TAG.sub(" ", text))).strip()


# Commons writes this when a file names no author in a form its tools can read, then
# guesses from the uploader: "No machine-readable author provided. Jonathunder assumed
# (based on copyright claims)." The credit is the name it settles on.
_ASSUMED_AUTHOR = re.compile(
    r"^No machine-readable author provided\.\s*(?P<name>.+?)\s+assumed\s*"
    r"\(based on copyright claims\)\.?$",
    re.DOTALL,
)


# What Commons' Credit field holds when it names where a file came from rather than who
# made it: "Own work", its machine-readable boilerplate, a transfer, a link.
_SOURCE_NOT_AUTHOR = re.compile(
    r"^(?:no machine-readable|own work|self[- ]?(?:made|photographed)|transferred from|"
    r"originally uploaded|uploaded by|https?://|www\.)",
    re.IGNORECASE,
)


def commons_credit(
    artist: str | None,
    credit: str | None = None,
    uploader: str | None = None,
    *,
    licence: str | None = None,
) -> str | None:
    """A Commons photograph's credit line: its author as a reader would write it, then
    where it came from.

    The author is the file's Artist field; where Commons records none, its Credit field
    if that names someone rather than a source ("Own work"), then the uploader, whom
    Commons itself assumes. A username keeps its name but not the ``~commonswiki`` tag
    that marks an account merged in from before global logins. With no one to name, the
    photograph is credited to its source, Commons, never to an invented "unknown
    photographer"; the owner keeps such photographs with their source stated rather than
    leaving them out, and the licence shows beside it.
    """
    name = _author(artist)
    if not name:
        text = strip_tags(credit or "")
        name = "" if _SOURCE_NOT_AUTHOR.match(text) else _author(text)
    if not name:
        name = _author(uploader)
    if name:
        return f"{name}, via Wikimedia Commons"
    return "Wikimedia Commons"


def commons_record_credit(record: dict[str, Any]) -> str | None:
    """``commons_credit`` for a licence record as ``commons_licence`` stores it."""
    return commons_credit(
        record.get("artist"),
        record.get("credit"),
        record.get("uploader"),
        licence=record.get("licence"),
    )


def _author(text: str | None) -> str:
    name = strip_tags(text or "")
    if match := _ASSUMED_AUTHOR.match(name):
        name = match.group("name")
    return re.sub(r"~commonswiki\b", "", name).strip()


# Characters a source lost in transit, put back where the right text is known. The NPS
# API returns Haleakalā's ʻokina as a question mark in some captions.
TEXT_REPAIRS = {"?Ohe?o": "ʻOheʻo", "Kīpahulu?": "Kīpahulu"}


def clean(text: Any) -> str | None:
    if not isinstance(text, str):
        return None
    cleaned = strip_tags(text)
    for damaged, repaired in TEXT_REPAIRS.items():
        cleaned = cleaned.replace(damaged, repaired)
    return cleaned or None


# MARK: - Raw store


def latest_raw_or_none(source: str) -> Path | None:
    try:
        return latest_raw(source) / source
    except SystemExit:
        return None


def latest_raw(source: str, *required: str) -> Path:
    """The newest dated snapshot whose ``source`` finished fetching, and holds ``required``.

    A fetch writes its ``source.json`` last, so a folder without one was cut off partway;
    reading it would ship partial data as if it were whole (the review of 17 November).
    """
    candidates = sorted(
        (
            path
            for path in config.RAW_DIR.iterdir()
            if (path / source / "source.json").is_file()
            and all((path / source / name).is_file() for name in required)
        ),
        reverse=True,
    )
    if not candidates:
        raise SystemExit(
            f"no complete raw/{source} yet: run `unigrids-pipeline reference` with network"
        )
    return candidates[0]
