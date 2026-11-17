"""Japan's share of the reference dataset.

The 35 national parks with their guides, sights, visitor centres and mountain huts; the
58 quasi-national parks; prefectures, outlines, climate, official brochures, and the
country's passenger rail with the stations near each national park.

Who says what: the Ministry of the Environment's own files give each national park its
area (``nps.zip``) and its visitors (自然公園等利用者数調, 2024); the Ministry's list gives
the quasi-national parks and the prefectures that run them; ``content/countries/jp/``
gives everything Unigrids wrote or chose; Wikidata and Wikipedia give the quasi-national
parks their English names, dates and leads; OpenStreetMap gives their outlines, the huts
and the railways. A figure no source carries is left out.
"""

from __future__ import annotations

import json
import math
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any
from urllib.parse import unquote

from PIL import Image

from ... import climate, ids, lands_build, outline, rawstore, reference_content
from ..abroad import elevation as abroad_elevation
from ..abroad import trails as abroad_trails
from ..base import BuildContext, Contribution
from ..common import (
    GALLERY_QUALITY,
    GALLERY_SIZE,
    HERO_QUALITY,
    HERO_SIZE,
    NATIONAL_PARK_TOLERANCE,
    OTHER_TOLERANCE,
    UnlicensedPhotographError,
    clean,
    commons_record_credit,
    encode_outline,
    extent,
    guide_image,
    photo_filename,
    resize,
)
from . import content, fetching, geometry, moe

COUNTRY = "JP"
# Japan keeps one time zone, so every place takes it directly rather than through
# ``common.assign_time_zones``, which reads a centre out at sea as Etc/GMT-9.
TIME_ZONE = "Asia/Tokyo"
MINISTRY = "Ministry of the Environment"
WIKIPEDIA_LICENCE = "CC BY-SA 4.0"

# A prefecture counts when it holds this share of a park's sampled land, the US rule.
PREFECTURE_SHARE = lands_build.STATE_SHARE
# Hero plus three: the guide's photos 2–4 make the gallery.
PHOTOS_PER_GUIDE = 4
# The Amami Islands are Kagoshima's (JP-46) but stamp with Okinawa: south of this
# latitude a Kagoshima place is in them. The Tokara Islands, north of it, are not.
AMAMI_NORTH = 28.9
# A guide sight further than this from its park's outline is reported for a second look.
SIGHT_TOLERANCE_KM = 5.0
STATION_REACH_M = fetching.STATION_REACH_KM * 1000
# Stop positions within this distance of a station, and of the same name, are its
# platforms on a line; any within the shorter distance are, whatever their name.
STOP_SAME_NAME_M = 600.0
STOP_ANY_NAME_M = 150.0


@dataclass
class Report:
    """What the build could not do for Japan, printed at the end of ``assemble``."""

    no_guide: list[str] = field(default_factory=list)
    no_photo: list[str] = field(default_factory=list)
    no_outline: list[str] = field(default_factory=list)
    unlicensed: list[str] = field(default_factory=list)
    far_sights: list[str] = field(default_factory=list)
    regions: list[str] = field(default_factory=list)
    no_visitors: list[str] = field(default_factory=list)
    unknown_themes: list[str] = field(default_factory=list)
    linked_images: list[str] = field(default_factory=list)
    partial_outlines: list[str] = field(default_factory=list)
    stations_from_rail: list[str] = field(default_factory=list)
    no_huts: list[str] = field(default_factory=list)

    def print(self) -> None:
        for label, entries in (
            ("national parks without a guide yet", self.no_guide),
            ("places without a photograph", self.no_photo),
            ("quasi-national parks shipped as a point (no OSM outline)", self.no_outline),
            ("OSM outlines refused as partial", self.partial_outlines),
            ("national parks with no Overpass answer yet: huts left out", self.no_huts),
            ("national parks whose nearby stations come from the rail services' own "
             "stops (no Overpass answer for the park yet)", self.stations_from_rail),
            ("photographs kept under a licence the US build would refuse", self.unlicensed),
            ("guide sights far from their park", self.far_sights),
            ("passport regions against the Ministry's office page", self.regions),
            ("national parks without a visitor figure", self.no_visitors),
            ("guide themes not in content/themes.json, left out", self.unknown_themes),
            ("national parks with no bundled guide photograph, shown with their Wikidata "
             "image linked instead", self.linked_images),
        ):
            if entries:
                print(f"    jp: {label} ({len(entries)}): {'; '.join(entries)}")


def assemble(context: BuildContext) -> Contribution:
    """Japan's places, sights, outlines, guides and layers, from ``raw/`` and
    ``content/countries/jp/``. Nothing here goes to the network."""
    report = Report()
    raw = _Raw.latest()
    print(f"    reading raw/{rawstore.version_of(raw.biodic)} for Japan")
    parks = content.national_parks()
    zones = fetching.park_zones(raw.biodic / fetching.NPS_ZIP, parks)
    outlines = {park_id: fetching.outline_of(by_zone) for park_id, by_zone in zones.items()}
    prefectures = raw.prefectures()
    place_registry = ids.country_registry("jp", "places")
    poi_registry = ids.country_registry("jp", "pois")

    places: list[dict[str, Any]] = []
    pois: list[dict[str, Any]] = []
    boundaries: dict[str, Any] = {}
    guides: dict[str, Any] = {}

    visitors = raw.visitors()
    offices = raw.offices()
    for park in parks:
        polygons = outlines[park["id"]]
        place, guide, park_pois = _national_park(
            park, polygons, prefectures, visitors, raw, context.images_dir, poi_registry, report
        )
        if offices is not None:
            _check_region(park, offices, report)
        boundaries[place["id"]] = encode_outline(polygons, NATIONAL_PARK_TOLERANCE)
        places.append(place)
        guides[place["id"]] = guide
        pois.extend(park_pois)
        pois.extend(_huts(park, polygons, raw, poi_registry, report))

    quasi = raw.quasi_parks()
    items = raw.wikidata()
    quasi_outlines = raw.quasi_outlines()
    for entry in quasi:
        place, polygons = _quasi_park(
            entry, items.get(entry.name) or {}, quasi_outlines, raw, prefectures,
            place_registry, report,
        )
        if polygons and (encoded := encode_outline(polygons, OTHER_TOLERANCE)):
            boundaries[place["id"]] = encoded
        places.append(place)

    # Trails from OpenStreetMap, measured as the US's are, and each park's lowest and
    # highest ground from Copernicus GLO-30.
    trail_registry = ids.country_registry("jp", "trails")
    pois_by_park: dict[str, list[dict[str, Any]]] = {}
    for poi in pois:
        pois_by_park.setdefault(poi["placeID"], []).append(poi)
    trails = abroad_trails.build(
        "jp", list(parks), outlines, pois_by_park, online=context.online, registry=trail_registry
    )
    abroad_elevation.attach_extremes(places, outlines, online=context.online)

    transport = raw.transport(parks, outlines, report)
    climate_dir = rawstore.latest(fetching.CLIMATE)
    normals = climate.build(climate_dir) if climate_dir else None
    documents = raw.documents(parks)
    report.print()
    return Contribution(
        places=places,
        pois=pois,
        boundaries={key: value for key, value in boundaries.items() if value},
        guides=guides,
        transport=transport,
        documents=documents,
        climate=normals,
        expects_summary={park["id"] for park in parks},
        trails=trails,
        registries=[place_registry, poi_registry, trail_registry],
    )


# MARK: - National parks


def _national_park(
    park: dict[str, Any],
    polygons: list[outline.Polygon],
    prefectures: geometry.Prefectures,
    visitors: dict[str, moe.AnnualVisitors],
    raw: _Raw,
    images_dir: Path,
    registry: ids.Registry,
    report: Report,
) -> tuple[dict[str, Any], dict[str, Any], list[dict[str, Any]]]:
    place_id = park["id"]
    guide = content.guide(place_id) or {}
    if not guide:
        report.no_guide.append(place_id)
    latitude, longitude = outline.label_point(polygons) or (0.0, 0.0)
    box = outline.bbox(polygons)
    facts = _facts(guide.get("facts") or {})
    figure = visitors.get(content.short_name(park))
    if figure:
        facts["annualVisits"] = figure.visitors
        facts["annualVisitsYear"] = figure.year
    else:
        report.no_visitors.append(place_id)

    photos = _guide_photos(place_id, guide, raw, images_dir, report)
    hero, gallery = (photos[0], photos[1:]) if photos else (None, [])
    official = moe.PARK_PAGE.format(slug=park["slug"])
    place: dict[str, Any] = {
        "id": place_id,
        "name": park["name"],
        "designation": "National Park",
        "kind": "nationalPark",
        "agency": "environmentMinistryJapan",
        "managedBy": MINISTRY,
        "country": COUNTRY,
        "subdivisions": _subdivisions(polygons, prefectures, (longitude, latitude)),
        "localNames": [{"language": "ja", "text": park["localName"]}],
        "passportRegion": park["passportRegion"],
        "timeZoneID": TIME_ZONE,
        "centre": {"latitude": round(latitude, 5), "longitude": round(longitude, 5)},
        "themes": _themes(place_id, guide, report),
        "facts": facts,
        "officialURL": official,
    }
    if box is not None:
        place["extent"] = extent([round(value, 5) for value in box])
    if reached_by := clean(park.get("reachedBy")):
        place["reachedBy"] = reached_by
    if summary := clean(guide.get("summary")):
        place["summary"] = summary
        place["summarySource"] = "Unigrids"
    if hero:
        place["image"] = hero
    elif fallback := raw.linked_image(raw.wikidata().get(park["localName"]) or {}):
        place["image"] = fallback
        report.linked_images.append(place_id)
    else:
        report.no_photo.append(place_id)

    park_pois = _sights(place_id, guide, polygons, registry, report)
    plan = dict(guide.get("planYourVisit") or {})
    sources = [*(guide.get("sources") or [])]
    if not any(official.rstrip("/") in (source.get("url") or "") for source in sources):
        sources.append({"title": f"{park['name']} National Park — japan.travel", "url": official})
    credits = list(guide.get("credits") or [
        "Text written for Unigrids from the Ministry of the Environment's park pages and "
        "the sources listed. Photographs from Wikimedia Commons, credited individually."
    ])
    # The outline is drawn from MOE's nps.zip; the area is the figure the guide was
    # written from, MOE's table of national parks. Each is credited to what it came from.
    if polygons:
        credits.append(
            f"Park outline: Ministry of the Environment, Japan (nps.zip, {raw.snapshot})"
        )
    if "areaHectares" in facts:
        credits.append("Park area: 国立公園一覧, Ministry of the Environment, Japan")
    if figure:
        credits.append(
            f"Visitors: 自然公園等利用者数調, Ministry of the Environment, Japan ({figure.year})"
        )
        sources.append({"title": "自然公園等利用者数調 — Ministry of the Environment",
                        "url": moe.STATISTICS_PAGE})
    result: dict[str, Any] = {
        "placeID": place_id,
        "contentVersion": guide.get("contentVersion", 1),
        "story": list(guide.get("story") or []),
        "howItWorks": list(guide.get("howItWorks") or []),
        "sightNotes": {
            poi["id"]: poi["summary"]
            for poi in park_pois
            if poi["kind"] in ("sight", "viewpoint") and poi.get("summary")
        },
        "planYourVisit": {key: value for key, value in plan.items() if value},
        "chronology": list(guide.get("chronology") or []),
        "safety": list(guide.get("safety") or []),
        "regulations": list(guide.get("regulations") or []),
        "credits": credits,
        "sources": sources,
        "fees": _fees(guide.get("fees") or []),
    }
    if hero:
        result["hero"] = hero
    if gallery:
        result["gallery"] = gallery
    for key in ("operatingHours", "weather", "directions"):
        if text := clean(guide.get(key)):
            result[key] = text
    return place, result, park_pois


def _themes(place_id: str, guide: dict[str, Any], report: Report) -> list[str]:
    known = {theme["id"] for theme in reference_content.themes()}
    themes = []
    for theme in guide.get("themes") or []:
        if theme in known:
            themes.append(theme)
        else:
            report.unknown_themes.append(f"{place_id}: {theme}")
    return themes


def _facts(written: dict[str, Any]) -> dict[str, Any]:
    """The guide's own figures, typed as the app decodes them. Nothing is derived."""
    facts: dict[str, Any] = {}
    if isinstance(written.get("establishedYear"), int):
        facts["establishedYear"] = written["establishedYear"]
    if isinstance(written.get("areaHectares"), int | float):
        facts["areaHectares"] = written["areaHectares"]
    seasons = [
        season for season in written.get("bestSeasons") or []
        if season in ("spring", "summer", "autumn", "winter")
    ]
    if seasons:
        facts["bestSeasons"] = seasons
    if isinstance(written.get("suggestedTime"), str) and written["suggestedTime"].strip():
        facts["suggestedTime"] = written["suggestedTime"].strip()
    return facts


def _fees(written: list[Any]) -> list[dict[str, Any]]:
    fees = []
    for fee in written:
        if not isinstance(fee, dict) or not fee.get("title") or not fee.get("cost"):
            continue
        entry: dict[str, Any] = {"title": fee["title"], "cost": fee["cost"]}
        if fee.get("detail"):
            entry["detail"] = fee["detail"]
        if isinstance(fee.get("amount"), int | float) and fee.get("currencyCode"):
            entry["amount"] = fee["amount"]
            entry["currencyCode"] = fee["currencyCode"]
        fees.append(entry)
    return fees


def _subdivisions(
    polygons: list[outline.Polygon],
    prefectures: geometry.Prefectures,
    centre: tuple[float, float],
) -> list[str]:
    """The prefectures holding a real share of the outline; for a park that is mostly
    sea and samples none, the prefecture nearest its centre."""
    # Sampled against the generalised outline: the shares come out the same, and a coast
    # of a hundred thousand vertices does not have to be crossed for every sample.
    simplified = outline.generalise(polygons, NATIONAL_PARK_TOLERANCE) or polygons
    codes = prefectures.of_polygons(simplified, PREFECTURE_SHARE)
    return codes or prefectures.nearest(centre)


def region_for(code: str, latitude: float | None = None) -> str:
    """The passport region a prefecture stamps in (Unigrids' eight-region split)."""
    number = int(code.removeprefix("JP-"))
    if number == 1:
        return "hokkaido"
    if 2 <= number <= 7:
        return "tohoku"
    if 8 <= number <= 14 or number == 19:
        return "kanto"
    if 15 <= number <= 24:
        return "chubu"
    if 25 <= number <= 30:
        return "kinki"
    if 31 <= number <= 39:
        return "chugokuShikoku"
    if number == 46 and latitude is not None and latitude < AMAMI_NORTH:
        return "okinawaAmami"
    if 40 <= number <= 46:
        return "kyushu"
    if number == 47:
        return "okinawaAmami"
    raise ValueError(f"no prefecture {code!r}")


def _check_region(
    park: dict[str, Any], offices: dict[str, moe.ParkOffices], report: Report
) -> None:
    """The content's region against the Ministry's office page. A disagreement is
    reported, never fixed here: the content file is the decision."""
    listed = offices.get(content.short_name(park))
    if listed is None:
        report.regions.append(f"{park['id']}: not on the office page")
    elif park["passportRegion"] not in listed.regions:
        report.regions.append(
            f"{park['id']}: content says {park['passportRegion']}, the Ministry files it "
            f"under {', '.join(listed.regions)} ({', '.join(listed.offices)})"
        )
    elif len(listed.regions) > 1:
        report.regions.append(
            f"{park['id']}: split across {', '.join(listed.regions)} on the office page; "
            f"content's {park['passportRegion']} is one of them"
        )


# MARK: - Sights, visitor centres and huts


def _sights(
    place_id: str,
    guide: dict[str, Any],
    polygons: list[outline.Polygon],
    registry: ids.Registry,
    report: Report,
) -> list[dict[str, Any]]:
    """The guide's ranked sights and its visitor centres, at the locations it gives.
    Sights are numbered in guide order; visitor centres share rank 0."""
    slug = content.slug(place_id)
    result = []
    rank = 0
    for sight in guide.get("sights") or []:
        name = (sight.get("name") or "").strip()
        location = sight.get("location")
        if not name or not isinstance(location, list) or len(location) != 2:
            print(f"    {place_id}: sight {name!r} has no location, left out")
            continue
        latitude, longitude = float(location[0]), float(location[1])
        kind = sight.get("kind") or "sight"
        if kind not in ("sight", "viewpoint", "visitorCentre"):
            kind = "sight"
        if kind != "visitorCentre":
            rank += 1
        if not geometry.near_many(
            polygons, [(longitude, latitude)], SIGHT_TOLERANCE_KM * 1000
        )[0]:
            report.far_sights.append(f"{place_id}: {name}")
        key = f"guide:{place_id}:{name}"
        poi: dict[str, Any] = {
            "id": ids.country_poi_id(
                registry, "jp", slug, key, latin_part(name) or f"sight {len(result) + 1}"
            ),
            "placeID": place_id,
            "kind": kind,
            "name": name,
            "location": {"latitude": round(latitude, 5), "longitude": round(longitude, 5)},
            "rank": 0 if kind == "visitorCentre" else rank,
            "hasStamp": False,
        }
        if note := clean(sight.get("note")):
            poi["summary"] = note
        if sight.get("url"):
            poi["url"] = sight["url"]
        result.append(poi)
    return result


def _huts(
    park: dict[str, Any],
    polygons: list[outline.Polygon],
    raw: _Raw,
    registry: ids.Registry,
    report: Report,
) -> list[dict[str, Any]]:
    """OpenStreetMap's mountain huts (山小屋) and shelters inside the park's outline."""
    fetched = raw.park_osm(park["id"])
    if fetched is None:
        report.no_huts.append(park["id"])
        return []
    elements = [
        element for element in fetched
        if (element.get("tags") or {}).get("tourism") in ("alpine_hut", "wilderness_hut")
    ]
    located = [(element, _osm_point(element)) for element in elements]
    located = [(element, point) for element, point in located if point]
    inside = geometry.contains_many(polygons, [point for _, point in located])
    huts = []
    seen: set[str] = set()
    for (element, (longitude, latitude)), hit in zip(located, inside, strict=True):
        tags = element.get("tags") or {}
        name = _display_name(tags)
        key = f"osm:{element['type']}/{element['id']}"
        if not hit or not name or key in seen:
            continue
        seen.add(key)
        huts.append({
            "id": ids.country_poi_id(
                registry, "jp", content.slug(park["id"]), key, _latin_name(tags)
            ),
            "placeID": park["id"],
            "kind": "hut",
            "name": name,
            "location": {"latitude": round(latitude, 5), "longitude": round(longitude, 5)},
            "rank": 0,
            "hasStamp": False,
        })
    return sorted(huts, key=lambda hut: hut["name"])


_CJK_BRACKETS = re.compile(r"\s*[(（][^()（）]*[\u3040-\u30ff\u3400-\u9fff][^()（）]*[)）]")
_CJK_RUN = re.compile(r"[\u3000-\u30ff\u3400-\u9fff\uff00-\uffef]+")


def latin_part(name: str) -> str | None:
    """The part of a name an identifier can be made from: ``Mount Fuji (富士山)`` →
    ``Mount Fuji``. ``None`` when the name is Japanese only."""
    text = _CJK_RUN.sub(" ", _CJK_BRACKETS.sub("", name))
    text = re.sub(r"\s+", " ", text).strip(" -–—·,")
    try:
        ids.romanised_slug(text)
    except ids.UnromanisedNameError:
        return None
    return text


def _osm_point(element: dict[str, Any]) -> tuple[float, float] | None:
    centre = element.get("center") or element
    if "lat" in centre and "lon" in centre:
        return (float(centre["lon"]), float(centre["lat"]))
    return None


def _display_name(tags: dict[str, Any]) -> str | None:
    """English where OSM has it, else the name as mapped (usually Japanese)."""
    return (tags.get("name:en") or tags.get("name") or "").strip() or None


def _latin_name(tags: dict[str, Any]) -> str | None:
    """A Latin-script name to build an identifier from, where OSM has one."""
    for key in ("name:en", "name:ja-Latn", "name:ja_rm"):
        if value := (tags.get(key) or "").strip():
            return value
    return None


# MARK: - Quasi-national parks


def english_name(item: dict[str, Any]) -> str | None:
    """``Ontakesan`` from the English Wikipedia title "Ontakesan Quasi-National Park",
    or from the Wikidata label where there is no article."""
    title = None
    if article := item.get("article"):
        title = unquote(article.rsplit("/wiki/", 1)[-1]).replace("_", " ")
    title = title or item.get("en")
    if not title:
        return None
    name = re.sub(r"\s+Quasi[- ]?National\s+Park$", "", title, flags=re.IGNORECASE).strip()
    return name or None


def _quasi_park(
    entry: moe.QuasiPark,
    item: dict[str, Any],
    osm_outlines: dict[str, list[outline.Polygon]],
    raw: _Raw,
    prefectures: geometry.Prefectures,
    registry: ids.Registry,
    report: Report,
) -> tuple[dict[str, Any], list[outline.Polygon] | None]:
    english = english_name(item)
    if not english:
        raise ValueError(f"{entry.name}: no English name on Wikidata or Wikipedia")
    place_id = registry.resolve(
        f"moe:{entry.name}", ids.country_place_id("jp", "qnp", english)
    )
    polygons = osm_outlines.get(entry.name) or osm_outlines.get(item.get("qid") or "")
    if polygons and (reason := _partial_outline(polygons, item)):
        report.partial_outlines.append(f"{english} ({entry.name}): {reason}")
        polygons = None
    if polygons:
        latitude, longitude = outline.label_point(polygons) or (0.0, 0.0)
        subdivisions = _subdivisions(polygons, prefectures, (longitude, latitude))
    else:
        latitude, longitude = item.get("coordinate") or (0.0, 0.0)
        subdivisions = list(entry.prefectures) or prefectures.nearest((longitude, latitude))
        report.no_outline.append(f"{english} ({entry.name})")
    place: dict[str, Any] = {
        "id": place_id,
        "name": english,
        "designation": "Quasi-National Park",
        "kind": "quasiNationalPark",
        "agency": "prefecture",
        "country": COUNTRY,
        "subdivisions": subdivisions,
        "localNames": [{"language": "ja", "text": entry.name}],
        "passportRegion": region_for(subdivisions[0], latitude),
        "timeZoneID": TIME_ZONE,
        "centre": {"latitude": round(latitude, 5), "longitude": round(longitude, 5)},
        "facts": {},
    }
    if managed := moe.managing_body(entry.prefectures):
        place["managedBy"] = managed
    if polygons and (box := outline.bbox(polygons)):
        place["extent"] = extent([round(value, 5) for value in box])
    if match := re.match(r"^(\d{4})-", item.get("inception") or ""):
        place["facts"]["establishedYear"] = int(match.group(1))
    if entry.url:
        place["officialURL"] = entry.url
    summary = raw.summaries().get(entry.name)
    if summary and summary.get("type") != "disambiguation" and summary.get("extract"):
        page = ((summary.get("content_urls") or {}).get("desktop") or {}).get("page")
        place["summary"] = lead(summary["extract"])
        place["summarySource"] = "Wikipedia"
        place["summaryLicence"] = WIKIPEDIA_LICENCE
        if page:
            place["summaryURL"] = page
            place["infoURL"] = page
    if image := raw.linked_image(item):
        place["image"] = image
    else:
        report.no_photo.append(place_id)
    return place, polygons


# An OSM outline whose area is outside this share of the park's published area is a
# part of the park mapped, or something else of its name, not the park.
OUTLINE_AREA_RANGE = (0.5, 2.0)
_HECTARES_PER_ACRE = 0.40468564224


def _partial_outline(polygons: list[outline.Polygon], item: dict[str, Any]) -> str | None:
    """Why an OSM outline cannot stand for the park, or ``None`` if it can: checked
    against the area Wikidata gives, where it gives one."""
    published = item.get("areaHectares")
    if not published:
        return None
    mapped = outline.geodesic_acres(polygons) * _HECTARES_PER_ACRE
    low, high = OUTLINE_AREA_RANGE
    if low <= mapped / published <= high:
        return None
    return (
        f"OSM outline is {mapped:,.0f} ha against {published:,.0f} ha published "
        f"({mapped / published:.0%}); shipped as a point"
    )


MAX_SENTENCES = 3
MAX_CHARACTERS = 620
_CJK = re.compile(r"[぀-ヿ㐀-鿿]")


def lead(extract: str) -> str:
    """The first sentences of a Wikipedia lead, short enough for a map card, without the
    bracketed Japanese name and reading the article opens with."""
    text = re.sub(r"\s+", " ", extract).strip()
    text = re.sub(r"\s*\([^()]*\)", lambda m: "" if _CJK.search(m.group()) else m.group(), text)
    text = re.sub(r"\s+([.,;:])", r"\1", text)
    sentences = re.split(r"(?<=[.!?])\s+(?=[A-Z0-9“\"])", text)
    chosen: list[str] = []
    for sentence in sentences:
        if chosen and (
            len(chosen) == MAX_SENTENCES or len(" ".join([*chosen, sentence])) > MAX_CHARACTERS
        ):
            break
        chosen.append(sentence)
    return " ".join(chosen).strip()


# MARK: - Photographs


def _photo_entry(image: dict[str, Any], *, asset_name: str | None = None) -> dict[str, Any]:
    """A photograph as the app carries it, credited, with its licence.

    ``guide_image`` is the shared rule; it refuses a licence the US build would not reuse.
    The owner's decision for this private app is that a licence is no reason to leave a
    photograph out, so such a photograph is kept here in the same shape — its credit and
    its own licence, and never marked public domain."""
    try:
        return guide_image(image, asset_name=asset_name)
    except UnlicensedPhotographError:
        credit = clean(image.get("credit"))
        licence = (image.get("licence") or "").strip()
        if not credit or not licence:
            raise
        entry: dict[str, Any] = {"credit": credit, "isPublicDomain": False, "licence": licence}
        if asset_name:
            entry["assetName"] = asset_name
        else:
            entry["url"] = image["url"]
        for key, field_name in (("caption", "title"), ("altText", "altText")):
            if text := clean(image.get(field_name)):
                entry[key] = text
        if image.get("sourceURL"):
            entry["sourceURL"] = image["sourceURL"]
        return entry


def _commons_credit(meta: dict[str, Any]) -> str | None:
    return commons_record_credit(meta)


def _guide_photos(
    place_id: str, guide: dict[str, Any], raw: _Raw, images_dir: Path, report: Report
) -> list[dict[str, Any]]:
    """The guide's photographs, hero first, resized into the app's images and credited
    from their Commons records."""
    entries = []
    for photo in (guide.get("photos") or [])[:PHOTOS_PER_GUIDE]:
        if not photo.get("file"):
            continue
        name = fetching.commons_name(photo["file"])
        meta = raw.licences().get(name)
        if not meta or not meta.get("licence"):
            print(f"    {place_id}: no Commons record for {name!r}, left out")
            continue
        credit = _commons_credit(meta)
        if credit is None:
            print(f"    {place_id}: no author to credit for {name!r}, left out")
            continue
        page = meta.get("descriptionURL") or f"https://commons.wikimedia.org/wiki/File:{name}"
        asset = f"{place_id}-{Path(photo_filename(page)).stem[:10]}.jpg"
        size, quality = (HERO_SIZE, HERO_QUALITY) if not entries else (
            GALLERY_SIZE, GALLERY_QUALITY
        )
        target = images_dir / asset
        source = fetching.photo_path(raw.commons, name) if raw.commons else None
        # Left alone once resized, as the US build does: rewriting the same bytes churns
        # an iCloud-synced checkout.
        if not target.exists():
            if source is None or not source.exists():
                print(f"    {place_id}: {name!r} not downloaded, left out")
                continue
            if not resize(source, target, _fitting(source, size), quality):
                continue
        image = {
            "url": meta.get("thumbURL") or page,
            "credit": credit,
            "licence": meta["licence"],
            "title": photo.get("caption"),
            "altText": photo.get("altText"),
            "sourceURL": page,
        }
        entry = _photo_entry(image, asset_name=asset)
        if not reference_content.is_reusable_licence(meta["licence"]):
            report.unlicensed.append(f"{name} ({meta['licence']})")
        entries.append(entry)
    return entries


def _fitting(source: Path, size: int) -> int:
    """The long edge to resize to: ``size``, or the photograph's own if it is smaller,
    so nothing is scaled up."""
    try:
        with Image.open(source) as picture:
            return min(size, max(picture.size))
    except OSError:
        return size


# MARK: - Raw data


class _Raw:
    """The newest snapshot of each Japanese source, read once."""

    def __init__(self, biodic: Path) -> None:
        self.biodic = biodic
        self.snapshot = rawstore.version_of(biodic)
        self.commons = rawstore.latest(fetching.COMMONS)
        self._cache: dict[str, Any] = {}

    @classmethod
    def latest(cls) -> _Raw:
        directory = rawstore.latest(fetching.BIODIC, fetching.NPS_ZIP)
        if directory is None:
            raise SystemExit(
                "no raw/<date>/jp-biodic/nps.zip yet: run Japan's fetch "
                "(`reference --countries jp`, or countries.load('jp').fetch())"
            )
        return cls(directory)

    def _once(self, key: str, load: Any) -> Any:
        if key not in self._cache:
            self._cache[key] = load()
        return self._cache[key]

    def prefectures(self) -> geometry.Prefectures:
        directory = rawstore.require(fetching.NATURAL_EARTH, fetching.PREFECTURES_FILE)
        payload = json.loads((directory / fetching.PREFECTURES_FILE).read_text())
        return geometry.Prefectures(amami_in_kagoshima([
            (feature["properties"]["iso_3166_2"], outline.polygons_of(feature["geometry"]))
            for feature in payload["features"]
        ]))

    def _moe(self, name: str) -> Path | None:
        directory = rawstore.latest(fetching.MOE, name)
        return directory / name if directory else None

    def visitors(self) -> dict[str, moe.AnnualVisitors]:
        path = self._moe("naturalpark_04.xlsx")
        return moe.park_visitors(path) if path else {}

    def offices(self) -> dict[str, moe.ParkOffices] | None:
        path = self._moe("offices.html")
        return moe.park_offices(path.read_text()) if path else None

    def quasi_parks(self) -> list[moe.QuasiPark]:
        path = self._moe("quasi-national-parks.html")
        if path is None:
            raise SystemExit("no raw jp-moe/quasi-national-parks.html: run Japan's fetch")
        return moe.quasi_parks(path.read_text())

    def wikidata(self) -> dict[str, dict[str, Any]]:
        def load() -> dict[str, dict[str, Any]]:
            directory = rawstore.latest(fetching.WIKIDATA, fetching.WIKIDATA_FILE)
            if directory is None:
                return {}
            payload = json.loads((directory / fetching.WIKIDATA_FILE).read_text())
            return fetching.wikidata_items(payload)

        return self._once("wikidata", load)

    def summaries(self) -> dict[str, Any]:
        return self._once("summaries", lambda: _json(fetching.WIKIPEDIA, fetching.SUMMARIES_FILE))

    def licences(self) -> dict[str, Any]:
        return self._once("licences", lambda: _json(fetching.COMMONS, fetching.LICENCES_FILE))

    def linked_image(self, item: dict[str, Any]) -> dict[str, Any] | None:
        """A Wikidata item's image (P18), linked rather than bundled, with its credit."""
        if not item.get("image"):
            return None
        meta = self.licences().get(fetching.commons_name(item["image"]))
        if not meta or not meta.get("thumbURL") or not meta.get("licence"):
            return None
        credit = _commons_credit(meta)
        if credit is None:
            return None
        return _photo_entry({
            "url": meta["thumbURL"],
            "credit": credit,
            "licence": meta["licence"],
            "sourceURL": meta.get("descriptionURL"),
        })

    def quasi_outlines(self) -> dict[str, list[outline.Polygon]]:
        """Japanese name or Wikidata ID → polygons, from the protected-area relations and
        ways OpenStreetMap names for a quasi-national park. Relations win over ways where
        a park is mapped as both, so nothing is drawn twice."""
        payload = _json(fetching.OSM, fetching.QUASI_OUTLINES_FILE)
        candidates: dict[str, list[dict[str, Any]]] = {}
        for element in payload.get("elements", []):
            tags = element.get("tags") or {}
            protected = (
                tags.get("boundary") in ("protected_area", "national_park")
                or tags.get("leisure") == "nature_reserve"
            )
            if not protected:
                continue
            for key in {tags.get("name", "").strip(), tags.get("wikidata", "").strip()} - {""}:
                candidates.setdefault(key, []).append(element)
        result: dict[str, list[outline.Polygon]] = {}
        for key, elements in candidates.items():
            relations = [element for element in elements if element["type"] == "relation"]
            polygons = [
                polygon for element in (relations or elements)
                for polygon in geometry.osm_polygons(element)
            ]
            if polygons:
                result[key] = polygons
        return result

    def park_osm(self, park_id: str) -> list[dict[str, Any]] | None:
        """The park's huts and nearby stations as Overpass answered, or ``None`` when
        no fetch has got an answer for it yet."""
        directory = rawstore.latest(fetching.OSM, f"parks/{park_id}.json")
        if directory is None:
            return None
        return json.loads((directory / "parks" / f"{park_id}.json").read_text()).get(
            "elements", []
        )

    def transport(
        self,
        parks: list[dict[str, Any]],
        outlines: dict[str, list[outline.Polygon]],
        report: Report,
    ) -> dict[str, list[dict[str, Any]]] | None:
        directory = rawstore.latest(fetching.OSM, "rail")
        if directory is None:
            return None
        network = RailNetwork.load(sorted((directory / "rail").glob("*.json")))
        stations: dict[int, dict[str, Any]] = {}
        for park in parks:
            coarse = outline.generalise(outlines[park["id"]], 0.008)
            fetched = self.park_osm(park["id"])
            if fetched is None:
                # No answer for this park yet: the stations the rail services name as
                # their stops still stand, though a station no service lists is missed.
                report.stations_from_rail.append(park["id"])
                fetched = network.member_stations()
            elements = [
                element for element in fetched
                if element.get("type") == "node"
                and (element.get("tags") or {}).get("railway") in ("station", "halt")
                and element["id"] not in stations
            ]
            near = geometry.near_many(
                coarse, [(e["lon"], e["lat"]) for e in elements], STATION_REACH_M
            )
            for element, hit in zip(elements, near, strict=True):
                if hit and (station := network.station(element)):
                    stations[element["id"]] = station
        rows = sorted(stations.values(), key=lambda row: row["code"])
        lines = network.lines()
        print(f"    transport: {len(lines)} rail lines, {len(rows)} stations near national parks")
        return {"railLines": lines, "railStations": rows}

    def documents(self, parks: list[dict[str, Any]]) -> dict[str, Any] | None:
        directory = rawstore.latest(fetching.DOCUMENTS, fetching.DOCUMENTS_FILE)
        if directory is None:
            return None
        found = json.loads((directory / fetching.DOCUMENTS_FILE).read_text())
        by_key = {moe.english_key(park["name"]): park for park in parks}
        by_slug = {park["slug"]: park for park in parks}
        result: dict[str, Any] = {}
        for document in found:
            if document.get("status") != 200:
                continue
            if not document.get("isPDF", "pdf" in (document.get("contentType") or "")):
                continue
            park = by_slug.get(document.get("slug") or "") or by_key.get(
                moe.english_key(document.get("park") or "")
            )
            if park is None:
                continue
            title = document.get("title") or f"{park['name']} National Park"
            is_brochure = (document.get("category") or "").upper() == "BROCHURE"
            if is_brochure and "brochure" not in title.lower():
                title = f"{title} brochure"
            row: dict[str, Any] = {
                "title": title,
                "url": document["url"],
                "kind": "brochure" if is_brochure else (
                    "map" if "map" in title.lower() else "other"
                ),
                "language": moe.document_language(title, document["url"]),
            }
            if document.get("bytes"):
                row["bytes"] = document["bytes"]
            entry = result.setdefault(park["id"], {"page": moe.BROCHURE_URL, "documents": []})
            if all(existing["url"] != row["url"] for existing in entry["documents"]):
                entry["documents"].append(row)
        for park in parks:
            result.setdefault(park["id"], {"page": moe.BROCHURE_URL, "documents": []})
        return result


# Natural Earth 5.1.1 draws the Amami Islands — Amami Ōshima, Kikai, Tokunoshima,
# Okinoerabu, Yoron — inside Okinawa (JP-47). They are Kagoshima's (JP-46). Okinawa's own
# islands that far north (Iheya, Izena, Iōtorishima) lie west of this meridian.
AMAMI_SOUTH, AMAMI_WEST = 27.0, 128.3


def amami_in_kagoshima(
    features: list[tuple[str, list[outline.Polygon]]],
) -> list[tuple[str, list[outline.Polygon]]]:
    """The prefecture features with Natural Earth's Amami polygons moved from Okinawa to
    Kagoshima, where they belong."""
    moved: list[outline.Polygon] = []
    result = []
    for code, polygons in features:
        if code == "JP-47":
            kept = []
            for polygon in polygons:
                south, west, north, east = outline.bbox([polygon]) or (0, 0, 0, 0)
                if (south + north) / 2 > AMAMI_SOUTH and (west + east) / 2 > AMAMI_WEST:
                    moved.append(polygon)
                else:
                    kept.append(polygon)
            polygons = kept
        result.append((code, polygons))
    return [
        (code, [*polygons, *moved] if code == "JP-46" else polygons)
        for code, polygons in result
    ]


def _json(source: str, name: str) -> dict[str, Any]:
    directory = rawstore.latest(source, name)
    return json.loads((directory / name).read_text()) if directory else {}


# MARK: - Rail


_DIRECTION = re.compile(
    r"\s*[(（][^()（）]*(?:→|⇒|=>|->|－＞|↔|⇔|⇄|<=>|〜|上り|下り|方面|\binbound\b|\boutbound\b)"
    r"[^()（）]*[)）]\s*$",
    re.IGNORECASE,
)
# "Kodama: Shin-Osaka => Okayama => Hakata": a route named by its stops after a colon.
_COLON_DIRECTION = re.compile(r"\s*:\s*[^:]*(?:→|⇒|=>|->|<=>|↔)[^:]*$")
_STOP_ROLES = frozenset({"stop", "stop_entry_only", "stop_exit_only", "", "station"})

# The ten Shinkansen lines, by the name their track carries in OpenStreetMap. Longest
# first, so 西九州新幹線 is not read as 九州新幹線.
SHINKANSEN = (
    ("西九州新幹線", "Nishi-Kyushu Shinkansen"),
    ("東海道新幹線", "Tokaido Shinkansen"),
    ("北海道新幹線", "Hokkaido Shinkansen"),
    ("山陽新幹線", "Sanyo Shinkansen"),
    ("九州新幹線", "Kyushu Shinkansen"),
    ("東北新幹線", "Tohoku Shinkansen"),
    ("上越新幹線", "Joetsu Shinkansen"),
    ("北陸新幹線", "Hokuriku Shinkansen"),
    ("山形新幹線", "Yamagata Shinkansen"),
    ("秋田新幹線", "Akita Shinkansen"),
)
_NAME_PARTS = re.compile(r"[;・()（）]")
# A stop takes the Shinkansen lines whose track passes this close.
SHINKANSEN_STOP_M = 400


def line_name(tags: dict[str, Any]) -> str | None:
    """A rail service's name for the map, in English where OSM has it, without the
    direction a route relation carries: ``JR中央線快速 (東京→高尾)`` → ``JR中央線快速``."""
    name = (tags.get("name:en") or tags.get("name") or "").strip()
    name = _DIRECTION.sub("", name).strip()
    name = _COLON_DIRECTION.sub("", name).strip()
    name = _strip_stops(name)
    return name or None


_ARROWS = ("<=>", "=>", "->", "→", "⇒", "↔", "⇔", "⇄", "－＞")


def _strip_stops(name: str) -> str:
    """What the patterns above miss: stops in brackets that hold brackets of their own,
    ``… Limited Express (Nishitetsu Fukuoka (Tenjin) => Omuta)``, and stops with no
    brackets at all, ``JR中央線・青梅線　立川 => 西立川``."""
    if not any(arrow in name for arrow in _ARROWS):
        return name
    if name.endswith((")", "）")):
        depth = 0
        for index in range(len(name) - 1, -1, -1):
            if name[index] in ")）":
                depth += 1
            elif name[index] in "(（":
                depth -= 1
                if depth == 0:
                    if any(arrow in name[index:] for arrow in _ARROWS):
                        return name[:index].strip()
                    break
        return name
    first = min(name.index(arrow) for arrow in _ARROWS if arrow in name)
    head = name[:first].rstrip()
    cut = max(head.rfind(" "), head.rfind("\u3000"))
    return head[:cut].strip() if cut > 0 else name


def shinkansen_line(tags: dict[str, Any]) -> str | None:
    """The Shinkansen line a stretch of track belongs to, from its own name:
    ``山陽新幹線;広島;14番線`` → ``Sanyo Shinkansen``. Services (Nozomi, Hayabusa) run
    across several lines, so a line is named by its track, never by the trains on it."""
    for key in ("name", "name:ja", "official_name"):
        for part in _NAME_PARTS.split(str(tags.get(key) or "")):
            for token, english in SHINKANSEN:
                if token in part:
                    return english
    english = str(tags.get("name:en") or "")
    for _, line in SHINKANSEN:
        if line.lower() in english.lower():
            return line
    return None


def _is_shinkansen(route: dict[str, Any], elements: dict[tuple[str, int], dict[str, Any]]) -> bool:
    tags = route.get("tags") or {}
    text = " ".join(str(tags.get(key) or "") for key in ("name", "name:en", "network", "ref"))
    if "新幹線" in text or "shinkansen" in text.lower():
        return True
    for member in route.get("members") or []:
        if member.get("type") != "way":
            continue
        way_tags = (elements.get(("way", member["ref"])) or {}).get("tags") or {}
        if way_tags.get("highspeed") == "yes" or shinkansen_line(way_tags):
            return True
    return False


class RailNetwork:
    """Japan's passenger rail services (``route=train`` relations) as fetched by region:
    their track for the ``railLines`` layer, and their stops for naming the lines that
    call at a station."""

    def __init__(self, elements: dict[tuple[str, int], dict[str, Any]]) -> None:
        self._elements = elements
        routes = {
            key[1]: element for key, element in elements.items()
            if key[0] == "relation"
            and (element.get("tags") or {}).get("route") == "train"
            and not _closed_service(element.get("tags") or {})
        }
        names: dict[int, str] = {}
        for key, element in elements.items():
            tags = element.get("tags") or {}
            if key[0] != "relation" or tags.get("type") != "route_master":
                continue
            master = line_name(tags)
            for member in element.get("members") or []:
                if member.get("type") == "relation" and master:
                    names.setdefault(member["ref"], master)
        shinkansen = {
            route_id for route_id, route in routes.items() if _is_shinkansen(route, elements)
        }
        # A Shinkansen service is not a line: its track is named way by way below.
        for route_id in shinkansen:
            names.pop(route_id, None)
        for route_id, route in routes.items():
            if route_id in shinkansen or route_id in names:
                continue
            if name := line_name(route.get("tags") or {}):
                names[route_id] = name
        self.routes = routes
        self.names = names
        self.shinkansen = shinkansen
        self._way_line = self._shinkansen_ways()
        track = self._track_grid()
        self._by_node: dict[int, set[str]] = {}
        self._grid: dict[tuple[int, int], list[tuple[float, float, str, str]]] = {}
        for route_id, route in routes.items():
            name = names.get(route_id)
            if not name and route_id not in shinkansen:
                continue
            for member in route.get("members") or []:
                if member.get("type") != "node" or member.get("role", "") not in _STOP_ROLES:
                    continue
                node = elements.get(("node", member["ref"]))
                if route_id in shinkansen:
                    calling = _lines_near(node, track) if node and "lat" in node else set()
                else:
                    calling = {name} if name else set()
                for line in calling:
                    self._by_node.setdefault(member["ref"], set()).add(line)
                    if node and "lat" in node:
                        stop_name = _station_key((node.get("tags") or {}).get("name") or "")
                        cell = (int(node["lat"] * 100), int(node["lon"] * 100))
                        self._grid.setdefault(cell, []).append(
                            (node["lat"], node["lon"], stop_name, line)
                        )

    def _shinkansen_ways(self) -> dict[int, str]:
        """Each Shinkansen service's track, way by way, under the line its name gives."""
        found: dict[int, str] = {}
        for route_id in self.shinkansen:
            for member in self.routes[route_id].get("members") or []:
                if member.get("type") != "way":
                    continue
                way = self._elements.get(("way", member["ref"])) or {}
                if line := shinkansen_line(way.get("tags") or {}):
                    found[member["ref"]] = line
        return found

    def _track_grid(self) -> dict[tuple[int, int], list[tuple[float, float, str]]]:
        grid: dict[tuple[int, int], list[tuple[float, float, str]]] = {}
        for way_id, line in self._way_line.items():
            for point in (self._elements.get(("way", way_id)) or {}).get("geometry") or []:
                if point:
                    cell = (int(point["lat"] * 100), int(point["lon"] * 100))
                    grid.setdefault(cell, []).append((point["lat"], point["lon"], line))
        return grid

    @classmethod
    def load(cls, paths: list[Path]) -> RailNetwork:
        elements: dict[tuple[str, int], dict[str, Any]] = {}
        for path in paths:
            for element in json.loads(path.read_text()).get("elements", []):
                elements.setdefault((element["type"], element["id"]), element)
        return cls(elements)

    def member_stations(self) -> list[dict[str, Any]]:
        """Station nodes the services list among their members."""
        return [
            element for (kind, _), element in self._elements.items()
            if kind == "node"
            and (element.get("tags") or {}).get("railway") in ("station", "halt")
        ]

    def lines_at(self, element: dict[str, Any]) -> list[str]:
        """The services that call at a station node: those it is a member of, and those
        with a stop beside it of the same name (or right beside it, whatever its name)."""
        found = set(self._by_node.get(element["id"], set()))
        latitude, longitude = element["lat"], element["lon"]
        own = _station_key((element.get("tags") or {}).get("name") or "")
        row, column = int(latitude * 100), int(longitude * 100)
        for cell_row in (row - 1, row, row + 1):
            for cell_column in (column - 1, column, column + 1):
                for lat, lon, stop_name, line in self._grid.get((cell_row, cell_column), []):
                    distance = _metres(latitude, longitude, lat, lon)
                    same_name = bool(own) and stop_name == own
                    if distance <= STOP_ANY_NAME_M or (same_name and distance <= STOP_SAME_NAME_M):
                        found.add(line)
        return sorted(found)

    def station(self, element: dict[str, Any]) -> dict[str, Any] | None:
        """A station record, or ``None`` for a subway, tram or monorail stop with no
        train service."""
        tags = element.get("tags") or {}
        name = _display_name(tags)
        if not name or not _takes_passengers(tags):
            return None
        lines = self.lines_at(element)
        urban = (
            tags.get("station") in ("subway", "light_rail", "monorail", "funicular", "tram")
            or tags.get("subway") == "yes"
        )
        if not lines and urban:
            return None
        return {
            "code": f"osm:node/{element['id']}",
            "name": name,
            "location": {
                "latitude": round(float(element["lat"]), 5),
                "longitude": round(float(element["lon"]), 5),
            },
            "country": COUNTRY,
            "lines": lines,
        }

    def lines(self) -> list[dict[str, Any]]:
        """One entry per service name, its track joined and generalised as the US's
        Amtrak routes are."""
        ways: dict[str, dict[int, list[tuple[float, float]]]] = {}
        for route_id, route in self.routes.items():
            name = self.names.get(route_id)
            if not name and route_id not in self.shinkansen:
                continue
            for member in route.get("members") or []:
                if member.get("type") != "way" or member.get("role") in ("platform",):
                    continue
                if route_id in self.shinkansen:
                    # Shared track is one line's, drawn once, whichever trains run on it.
                    name = self._way_line.get(member["ref"])
                    if not name:
                        continue
                way = self._elements.get(("way", member["ref"]))
                if not way or not way.get("geometry"):
                    continue
                points = [(node["lon"], node["lat"]) for node in way["geometry"] if node]
                if len(points) >= 2:
                    ways.setdefault(name, {})[member["ref"]] = points
        entries = []
        for name in sorted(ways):
            paths = lands_build._generalised(
                list(ways[name].values()), lands_build.RAIL_TOLERANCE
            )
            if paths:
                entries.append(lands_build._route_entry(name, paths))
        return entries


def _lines_near(
    node: dict[str, Any], grid: dict[tuple[int, int], list[tuple[float, float, str]]]
) -> set[str]:
    """The Shinkansen lines whose track passes a stop: Tokyo's Tokaido and Tohoku."""
    row, column = int(node["lat"] * 100), int(node["lon"] * 100)
    found: set[str] = set()
    for cell_row in (row - 1, row, row + 1):
        for cell_column in (column - 1, column, column + 1):
            for lat, lon, line in grid.get((cell_row, cell_column), []):
                if _metres(node["lat"], node["lon"], lat, lon) <= SHINKANSEN_STOP_M:
                    found.add(line)
    return found


def _takes_passengers(tags: dict[str, Any]) -> bool:
    """Not a signal station (信号場), where trains pass and wait but nobody boards."""
    names = " ".join(str(tags.get(key) or "") for key in ("name", "name:en"))
    return not (
        re.search(r"信号[場所]|signal (?:station|stop)", names, re.IGNORECASE)
        or tags.get("passenger") == "no"
        or tags.get("station") == "signal"
    )


def _closed_service(tags: dict[str, Any]) -> bool:
    """A relation for a line that no longer runs: mapped for history (北海道の廃止国鉄線)."""
    names = " ".join(str(tags.get(key) or "") for key in ("name", "name:en", "note"))
    return (
        bool(re.search(r"廃止|廃線|abolished|abandoned|disused", names, re.IGNORECASE))
        or any(tags.get(key) == "yes" for key in ("disused", "abandoned", "historic"))
        or tags.get("state") in ("disused", "abandoned")
    )


def _station_key(name: str) -> str:
    return re.sub(r"\s|駅$", "", name)


def _metres(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    x = math.radians(lon2 - lon1) * math.cos(math.radians((lat1 + lat2) / 2))
    y = math.radians(lat2 - lat1)
    return math.hypot(x, y) * 6_371_008.8
