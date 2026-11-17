"""Norway's share of the reference dataset.

The 48 national parks with their guides; every landscape protection area and every nature
reserve of 10 km² or more; their outlines; the guides' sights and visitor centres and the
huts OpenStreetMap knows inside each park; the rail stations near the parks and the
passenger lines through them; each park's climate and official page.

The split of responsibility is the US build's: Miljødirektoratet's Naturvernområder says
what an area is — its official names, outline, municipalities, manager and dates — and the
curated guides say what Unigrids wrote or chose. Nothing here invents a figure. A value
the sources do not carry is left out, and the app renders it as absent.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from ... import climate, geo, ids, outline, rawstore, reference_content
from ..abroad import elevation as abroad_elevation
from ..abroad import trails as abroad_trails
from ..base import BuildContext, Contribution
from ..common import (
    GALLERY_COUNT,
    GALLERY_QUALITY,
    GALLERY_SIZE,
    HERO_QUALITY,
    HERO_SIZE,
    NATIONAL_PARK_TOLERANCE,
    OTHER_TOLERANCE,
    assign_time_zones,
    clean,
    commons_credit,
    encode_outline,
    extent,
    guide_image,
    photo_filename,
    resize,
)
from . import content, rules, transport, wiki
from .fetching import (
    CLIMATE,
    COMMONS,
    COUNTIES,
    COUNTIES_FILE,
    DOCUMENTS,
    NATURVERN,
    OSM,
    PHOTOS,
    RESTRICTIONS,
    WIKIDATA,
    WIKIPEDIA,
    Area,
    national_parks,
    photo_url,
    read_areas,
    read_counties,
    read_wikidata,
    second_tier,
)

COUNTRY = "NO"
AGENCY = "environmentAgencyNorway"
TIME_ZONES = {"svalbard": "Arctic/Longyearbyen"}
MAINLAND_TIME_ZONE = "Europe/Oslo"

DESIGNATIONS = {
    "np": ("National Park", "nationalPark"),
    "lvo": ("Protected Landscape", "protectedLandscape"),
    "nr": ("Nature Reserve", "natureReserve"),
}

# What a guide may say about a park's facts; anything else in it is not a fact the app
# shows, and elevation is measured, not written (``content/countries/README.md``).
FACT_KEYS = ("establishedYear", "areaHectares", "bestSeasons", "suggestedTime")
SEASONS = frozenset({"spring", "summer", "autumn", "winter"})
POI_KINDS = frozenset({"sight", "viewpoint", "visitorCentre", "entrance", "trailhead"})
RANKED_KINDS = frozenset({"sight", "viewpoint"})

DEFAULT_CREDITS = [
    "Text written for Unigrids. Facts checked against Norges nasjonalparker "
    "(Miljødirektoratet) and the sources below.",
    "Park outline and official names: Naturvernområder, Miljødirektoratet, under the "
    "Norwegian Licence for Open Government Data (NLOD) 2.0. The outline is simplified by "
    "Unigrids.",
]


def assemble(context: BuildContext) -> Contribution:
    """Every Norwegian place, sight, outline, guide and layer, from the raw store and
    ``content/countries/no/``. Offline by design: everything the build needs is fetched
    by ``fetch``; ``context.online`` only lets trails and elevation tiles that were not
    fetched be fetched now."""
    naturvern_dir = rawstore.latest(NATURVERN, "national-parks.geojson")
    if naturvern_dir is None:
        raise SystemExit(f"no raw/{NATURVERN} yet: run Norway's fetch with network")
    print(f"    reading raw/{naturvern_dir.parent.name}/{NATURVERN}")
    areas = read_areas(naturvern_dir)
    sources = _Sources()

    place_registry = ids.country_registry("no", "places")
    poi_registry = ids.country_registry("no", "pois")

    places: list[dict[str, Any]] = []
    pois: list[dict[str, Any]] = []
    boundaries: dict[str, Any] = {}
    guides: dict[str, Any] = {}
    report = _Report()
    parks: list[dict[str, Any]] = []
    park_outlines: dict[str, Any] = {}

    for park, area in national_parks(areas):
        if area is None or not area.polygons:
            report.add("parks without an outline", park["id"])
            continue
        parks.append(park)
        park_outlines[park["id"]] = area.polygons
        place, guide, park_pois = _national_park(
            park, area, sources, poi_registry, context, report
        )
        outline_entry = encode_outline(area.polygons, NATIONAL_PARK_TOLERANCE)
        if outline_entry:
            boundaries[place["id"]] = outline_entry
            place["extent"] = extent(outline_entry["bbox"])
        else:
            report.add("parks without an outline", park["id"])
        places.append(place)
        pois.extend(park_pois)
        guides[place["id"]] = guide

    for area in second_tier(areas):
        # Outlined first, so an area that will not ship is never given an identifier.
        outline_entry = encode_outline(area.polygons, OTHER_TOLERANCE)
        if not outline_entry:
            report.add("left out: no outline at the map's scale", area.naturvern_id)
            continue
        place = _second_tier_place(area, sources, place_registry, report)
        if place is None:
            continue
        boundaries[place["id"]] = outline_entry
        place["extent"] = extent(outline_entry["bbox"])
        places.append(place)

    # Trails from Kartverket's Turrutebasen (OpenStreetMap where it has none), measured as
    # the US's are; and each park's lowest and highest ground, from Copernicus GLO-30.
    trail_registry = ids.country_registry("no", "trails")
    pois_by_park: dict[str, list[dict[str, Any]]] = {}
    for poi in pois:
        pois_by_park.setdefault(poi["placeID"], []).append(poi)
    trails = abroad_trails.build(
        "no", parks, park_outlines, pois_by_park, online=context.online, registry=trail_registry
    )
    abroad_elevation.attach_extremes(places, park_outlines, online=context.online)

    _zone(places, report)
    _report_reserves(naturvern_dir, areas)
    _report_restrictions(areas)
    rail = _transport(areas, sources)
    normals = climate.build(sources.climate) if sources.climate else None
    documents = _documents(places, sources)

    kinds: dict[str, int] = {}
    for poi in pois:
        kinds[poi["kind"]] = kinds.get(poi["kind"], 0) + 1
    tiers: dict[str, int] = {}
    for place in places:
        tiers[place["kind"]] = tiers.get(place["kind"], 0) + 1
    print(f"    places: {tiers}; points of interest: {kinds}")
    report.print()

    return Contribution(
        places=places,
        pois=pois,
        boundaries=boundaries,
        guides=guides,
        transport=rail,
        documents=documents,
        climate=normals,
        expects_summary={place["id"] for place in places if place["kind"] == "nationalPark"},
        trails=trails,
        registries=[place_registry, poi_registry, trail_registry],
    )


# MARK: - Raw sources


class _Sources:
    """The newest fetched copy of each source the build reads, or nothing."""

    def __init__(self) -> None:
        counties_dir = rawstore.latest(COUNTIES, COUNTIES_FILE)
        self.counties = (
            rules.Counties(read_counties(counties_dir / COUNTIES_FILE)) if counties_dir else None
        )
        if self.counties is None:
            print(f"    no raw/{COUNTIES}: regions from the municipality list alone")
        self.index, self.candidates = read_wikidata(rawstore.latest(WIKIDATA, "naturbase.json"))
        self.summaries = _json(rawstore.latest(WIKIPEDIA, "summaries.json"), "summaries.json")
        self.licences = _json(rawstore.latest(COMMONS, "licences.json"), "licences.json")
        self.photos = rawstore.latest(PHOTOS)
        self.documents = _json(rawstore.latest(DOCUMENTS, "links.json"), "links.json")
        self.osm = rawstore.latest(OSM)
        # Every Overpass answer about huts and stations: by region, and park by park as
        # an earlier fetch asked.
        self.osm_payloads = [
            json.loads(path.read_text())
            for folder in ("regions", "parks")
            for path in sorted((self.osm / folder).glob("*.json") if self.osm else [])
        ]
        found: dict[str, dict[str, Any]] = {}
        for payload in self.osm_payloads:
            for element in transport.huts(payload):
                found.setdefault(transport.key_of(element), element)
        self.huts = [found[key] for key in sorted(found)]
        self.climate = rawstore.latest(CLIMATE)
        self._fine_counties: rules.Counties | None = None

    @property
    def fine_counties(self) -> rules.Counties | None:
        """The counties drawn closer, for whether a station is in Norway at all: a coastal
        station lies within the coarse outlines' 500 m of the sea."""
        if self._fine_counties is None:
            counties_dir = rawstore.latest(COUNTIES, COUNTIES_FILE)
            if counties_dir is None:
                return None
            self._fine_counties = rules.Counties(
                read_counties(counties_dir / COUNTIES_FILE), tolerance=0.0005
            )
        return self._fine_counties


def _json(directory: Path | None, name: str) -> dict[str, Any]:
    if directory is None or not (directory / name).exists():
        return {}
    return json.loads((directory / name).read_text())


class _Report:
    """What the build could not do, printed once at the end."""

    def __init__(self) -> None:
        self.lines: dict[str, list[str]] = {}

    def add(self, heading: str, item: str) -> None:
        self.lines.setdefault(heading, []).append(item)

    def print(self) -> None:
        for heading, items in self.lines.items():
            more = f" and {len(items) - 30} more" if len(items) > 30 else ""
            shown = ", ".join(items[:30]) + more
            print(f"    {heading} ({len(items)}): {shown}")


# MARK: - Where a place is


def _locate(area: Area, sources: _Sources) -> tuple[list[str], str | None]:
    """The place's counties, largest share first, as ``NO-nn`` codes, and its region."""
    listed = rules.county_codes(area.properties.get("kommune"))
    shares: dict[str, int] = {}
    if sources.counties is not None and rules.SVALBARD not in listed:
        shares = sources.counties.shares(area.polygons, among=listed or None)
        if not listed:
            listed = sorted(shares, key=lambda code: -shares[code])
    ordered = rules.ordered_counties(listed, shares)
    region = rules.region_of(rules.main_county(listed, shares))
    return [rules.subdivision(code) for code in ordered], region


def _zone(places: list[dict[str, Any]], report: _Report) -> None:
    """Each place's time zone at its centre, held to the two Norway keeps: a centre the
    zone finder places anywhere else (at sea, over a border) takes its region's."""
    assign_time_zones(places)
    for place in places:
        expected = TIME_ZONES.get(place.get("passportRegion") or "", MAINLAND_TIME_ZONE)
        if place.get("timeZoneID") != expected:
            if place.get("timeZoneID"):
                report.add(
                    "time zones corrected", f"{place['id']} {place['timeZoneID']}→{expected}"
                )
            place["timeZoneID"] = expected


def _centre(area: Area) -> dict[str, float]:
    latitude, longitude = area.centre or (0.0, 0.0)
    return {"latitude": round(latitude, 5), "longitude": round(longitude, 5)}


# MARK: - National parks


def _national_park(
    park: dict[str, Any],
    area: Area,
    sources: _Sources,
    poi_registry: ids.Registry,
    context: BuildContext,
    report: _Report,
) -> tuple[dict[str, Any], dict[str, Any], list[dict[str, Any]]]:
    place_id = park["id"]
    guide = content.guide(place_id)
    if guide is None:
        report.add("parks without a guide", place_id)
        guide = {}
    subdivisions, region = _locate(area, sources)
    if park.get("svalbard"):
        region = "svalbard"
    names, unknown = rules.local_names(area.properties.get("offisieltNavn"))
    for form in unknown:
        report.add("official names with no language", f"{place_id}: {form}")

    hero, gallery = _park_photos(place_id, guide, sources, context.images_dir, report)
    if hero is None:
        report.add("parks without a photograph", place_id)
    links = sources.documents.get(place_id) or {}
    official = links.get("english") or links.get("page") or content.first_source_url(place_id)

    place: dict[str, Any] = {
        "id": place_id,
        "name": park["name"],
        "designation": DESIGNATIONS["np"][0],
        "kind": DESIGNATIONS["np"][1],
        "agency": AGENCY,
        "country": COUNTRY,
        "subdivisions": subdivisions,
        "centre": _centre(area),
        "themes": _themes(place_id, guide, report),
        "facts": _facts(place_id, guide, report),
    }
    if official:
        place["officialURL"] = official
    if summary := clean(guide.get("summary")):
        place["summary"] = summary
        place["summarySource"] = "Unigrids"
    if hero:
        place["image"] = hero
    if names:
        place["localNames"] = names
    if manager := clean(area.properties.get("forvaltningsmyndighet")):
        place["managedBy"] = manager
    if reached_by := clean(park.get("reachedBy")):
        place["reachedBy"] = reached_by
    if region:
        place["passportRegion"] = region
    else:
        report.add("places without a region", place_id)

    pois = _guide_pois(place_id, guide, poi_registry, report)
    pois.extend(_huts(place_id, area, sources, poi_registry))

    sources_list = []
    for source in guide.get("sources") or []:
        if not isinstance(source, dict) or not (source.get("title") or source.get("url")):
            continue
        entry = {"title": clean(source.get("title")) or source["url"]}
        if source.get("url"):
            entry["url"] = source["url"]
        sources_list.append(entry)
    page = links.get("page") or official
    if page and not any("norgesnasjonalparker.no" in (s.get("url") or "") for s in sources_list):
        sources_list.append({"title": f"{park['name']} — Norges nasjonalparker", "url": page})

    plan = _plan(guide.get("planYourVisit"))
    record: dict[str, Any] = {
        "placeID": place_id,
        "contentVersion": guide.get("contentVersion", 1),
        "story": _strings(guide.get("story")),
        "howItWorks": _strings(guide.get("howItWorks")),
        "sightNotes": {
            poi["id"]: poi["summary"]
            for poi in pois
            if poi["kind"] in RANKED_KINDS and poi.get("summary")
        },
        "planYourVisit": plan,
        "chronology": [
            {"year": str(entry["year"]), "text": entry["text"]}
            for entry in guide.get("chronology") or []
            if isinstance(entry, dict) and entry.get("year") and entry.get("text")
        ],
        "safety": _strings(guide.get("safety")),
        "regulations": _strings(guide.get("regulations")),
        "credits": _credits(guide),
        "sources": sources_list,
        "fees": _fees(guide.get("fees")),
    }
    if hero:
        record["hero"] = hero
    if gallery:
        record["gallery"] = gallery
    for key in ("operatingHours", "weather", "directions"):
        if text := clean(guide.get(key)):
            record[key] = text
    return place, record, pois


def _credits(guide: dict[str, Any]) -> list[str]:
    """The guide's own credits, or the default; either way ending with the data credit
    NLOD asks for, which says the outline was changed (simplified) by Unigrids."""
    credits = _strings(guide.get("credits")) or DEFAULT_CREDITS[:1]
    if not any("NLOD" in line for line in credits):
        credits.append(DEFAULT_CREDITS[1])
    return credits


def _strings(value: Any) -> list[str]:
    return [item.strip() for item in value or [] if isinstance(item, str) and item.strip()]


def _facts(place_id: str, guide: dict[str, Any], report: _Report) -> dict[str, Any]:
    """The facts a guide gives, as the app reads them; a value of the wrong shape is
    reported and left out rather than repaired into something the guide did not say."""
    given = guide.get("facts") or {}
    facts: dict[str, Any] = {}
    year = given.get("establishedYear")
    if isinstance(year, int) and 1800 < year < 2100:
        facts["establishedYear"] = year
    elif year is not None:
        report.add("facts left out", f"{place_id} establishedYear {year!r}")
    hectares = given.get("areaHectares")
    if isinstance(hectares, int | float) and hectares > 0:
        facts["areaHectares"] = hectares
    elif hectares is not None:
        report.add("facts left out", f"{place_id} areaHectares {hectares!r}")
    seasons = [season for season in given.get("bestSeasons") or [] if season in SEASONS]
    if seasons:
        facts["bestSeasons"] = seasons
    if suggested := clean(given.get("suggestedTime")):
        facts["suggestedTime"] = suggested
    for key in given:
        if key not in FACT_KEYS:
            report.add("facts left out", f"{place_id} {key}")
    return facts


def _themes(place_id: str, guide: dict[str, Any], report: _Report) -> list[str]:
    themes = []
    for theme in guide.get("themes") or []:
        if theme in content.theme_ids():
            themes.append(theme)
        else:
            report.add("unknown themes", f"{place_id} {theme}")
    return themes


def _plan(plan: Any) -> dict[str, Any]:
    """Plan your visit, with only the keys that say something, and closure months that
    are months."""
    if not isinstance(plan, dict):
        return {}
    result: dict[str, Any] = {}
    for key, value in plan.items():
        if key == "seasonalClosureMonths":
            months = sorted({m for m in value or [] if isinstance(m, int) and 1 <= m <= 12})
            if months:
                result[key] = months
        elif isinstance(value, str):
            if value.strip():
                result[key] = value.strip()
        elif isinstance(value, list):
            if items := _strings(value):
                result[key] = items
    return result


def _fees(fees: Any) -> list[dict[str, Any]]:
    """Fees as the guide gives them; the amount travels only as a number with its
    currency, so the app can format it in the reader's way."""
    result = []
    for fee in fees or []:
        if not isinstance(fee, dict) or not fee.get("title") or not fee.get("cost"):
            continue
        entry: dict[str, Any] = {"title": fee["title"].strip(), "cost": fee["cost"].strip()}
        if detail := clean(fee.get("detail")):
            entry["detail"] = detail
        amount, currency = fee.get("amount"), fee.get("currencyCode")
        if isinstance(amount, int | float) and isinstance(currency, str) and currency.strip():
            entry["amount"] = amount
            entry["currencyCode"] = currency.strip().upper()
        result.append(entry)
    return result


# MARK: - Photographs


def _credit(licence: dict[str, Any]) -> str:
    return commons_credit(licence.get("artist"))


def photo_entry(image: dict[str, Any], *, asset_name: str | None = None) -> dict[str, Any] | None:
    """A Commons photograph as a guide or place carries it.

    The owner's rule for this private app: a licence is not a reason to leave a
    photograph out, but every photograph keeps its credit and licence and is marked public
    domain only when its licence says so. One with no licence recorded at all cannot keep
    it, and is left out."""
    licence = (image.get("licence") or "").strip()
    if not clean(image.get("credit")) or not licence:
        return None
    if reference_content.is_reusable_licence(licence):
        return guide_image(image, asset_name=asset_name)
    entry: dict[str, Any] = {"credit": clean(image["credit"]), "isPublicDomain": False}
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
    entry["licence"] = licence
    return entry


def _park_photos(
    place_id: str,
    guide: dict[str, Any],
    sources: _Sources,
    images_dir: Path,
    report: _Report,
) -> tuple[dict[str, Any] | None, list[dict[str, Any]]]:
    """The guide's first photograph as the hero and the next three as the gallery, each
    resized into the app's bundle and credited from Commons."""
    hero: dict[str, Any] | None = None
    gallery: list[dict[str, Any]] = []
    for photo in guide.get("photos") or []:
        if len(gallery) == GALLERY_COUNT:
            break
        name = content.commons_name((photo or {}).get("file"))
        if not name:
            continue
        licence = sources.licences.get(name)
        if not licence:
            report.add("photographs with no Commons record", f"{place_id}: {name}")
            continue
        url = photo_url(name)
        local = photo_filename(url)
        asset = f"{place_id}-{Path(local).stem[:10]}.jpg"
        size, quality = (HERO_SIZE, HERO_QUALITY) if hero is None else (
            GALLERY_SIZE, GALLERY_QUALITY
        )
        # A photograph already resized is left alone, as the US build does: rewriting the
        # same bytes churns a synced checkout.
        source = sources.photos / local if sources.photos else None
        if not (images_dir / asset).exists():
            if source is None or not source.exists():
                report.add("photographs not downloaded", f"{place_id}: {name}")
                continue
            if not resize(source, images_dir / asset, size, quality):
                report.add("photographs that would not resize", f"{place_id}: {name}")
                continue
        entry = photo_entry(
            {
                "url": url,
                "credit": _credit(licence),
                "licence": licence.get("licence"),
                "title": photo.get("caption"),
                "altText": photo.get("altText"),
                "sourceURL": licence.get("descriptionURL"),
            },
            asset_name=asset,
        )
        if entry is None:
            report.add("photographs without a licence", f"{place_id}: {name}")
            continue
        if hero is None:
            hero = entry
        else:
            gallery.append(entry)
    return hero, gallery


def _linked_image(name: str | None, sources: _Sources) -> dict[str, Any] | None:
    """A second-tier place's Wikidata image, linked rather than bundled, as the US links
    the photographs of places without a guide."""
    licence = sources.licences.get(name or "")
    if not licence or not licence.get("thumbURL"):
        return None
    return photo_entry({
        "url": licence["thumbURL"],
        "credit": _credit(licence),
        "licence": licence.get("licence"),
        "sourceURL": licence.get("descriptionURL"),
    })


# MARK: - Points of interest


def _guide_pois(
    place_id: str, guide: dict[str, Any], registry: ids.Registry, report: _Report
) -> list[dict[str, Any]]:
    """The guide's sights, ranked in the guide's order, and its visitor centres."""
    slug = content.park_slug(place_id)
    pois: list[dict[str, Any]] = []
    seen: set[str] = set()
    rank = 0
    for sight in guide.get("sights") or []:
        name = clean((sight or {}).get("name"))
        location = _location((sight or {}).get("location"))
        kind = (sight or {}).get("kind") or "sight"
        if not name or location is None or kind not in POI_KINDS:
            report.add("guide sights left out", f"{place_id}: {name or sight!r}")
            continue
        poi_id = ids.country_poi_id(registry, "no", slug, f"guide:{place_id}:{name}", name)
        if poi_id in seen:
            continue
        seen.add(poi_id)
        if kind in RANKED_KINDS:
            rank += 1
        poi: dict[str, Any] = {
            "id": poi_id,
            "placeID": place_id,
            "kind": kind,
            "name": name,
            "location": location,
            "rank": rank if kind in RANKED_KINDS else 0,
            "hasStamp": False,
        }
        if note := clean(sight.get("note")):
            poi["summary"] = note
        if isinstance(sight.get("url"), str) and sight["url"].startswith("http"):
            poi["url"] = sight["url"]
        pois.append(poi)
    return pois


def _location(value: Any) -> dict[str, float] | None:
    if not isinstance(value, list | tuple) or len(value) != 2:
        return None
    latitude, longitude = value
    if not isinstance(latitude, int | float) or not isinstance(longitude, int | float):
        return None
    if not (57.0 <= latitude <= 81.5 and 4.0 <= longitude <= 34.0):
        return None
    return {"latitude": round(float(latitude), 5), "longitude": round(float(longitude), 5)}


def _huts(
    place_id: str, area: Area, sources: _Sources, registry: ids.Registry
) -> list[dict[str, Any]]:
    """The named huts OpenStreetMap maps inside the park's own outline."""
    box = area.box
    if box is None:
        return []
    slug = content.park_slug(place_id)
    pois = []
    for element in sources.huts:
        point = transport.point_of(element)
        assert point is not None
        latitude, longitude = point
        if not _within(box, point) or not _inside(area, longitude, latitude):
            continue
        tags = element.get("tags") or {}
        name = tags["name"].strip()
        poi: dict[str, Any] = {
            "id": ids.country_poi_id(registry, "no", slug, transport.key_of(element), name),
            "placeID": place_id,
            "kind": "hut",
            "name": name,
            "location": {"latitude": round(latitude, 5), "longitude": round(longitude, 5)},
            "rank": 0,
            "hasStamp": False,
        }
        if summary := rules.hut_summary(tags):
            poi["summary"] = summary
        website = tags.get("website") or tags.get("contact:website") or ""
        if website.startswith(("http://", "https://")):
            poi["url"] = website
        pois.append(poi)
    return sorted(pois, key=lambda poi: poi["name"])


def _inside(area: Area, longitude: float, latitude: float) -> bool:
    return outline.contains(area.polygons, longitude, latitude)


# MARK: - Second tier


def _second_tier_place(
    area: Area, sources: _Sources, registry: ids.Registry, report: _Report
) -> dict[str, Any] | None:
    """A landscape protection area or nature reserve: located, named, dated and measured
    from Naturvernområder, and described by its Wikipedia lead where it has one."""
    subdivisions, region = _locate(area, sources)
    if not subdivisions or not region:
        report.add(
            "left out: in no county or region", f"{area.naturvern_id} {area.name}"
        )
        return None
    designation, kind = DESIGNATIONS[area.tier]
    name = area.name
    try:
        proposed = ids.country_place_id("no", area.tier, name)
    except ids.UnromanisedNameError:
        proposed = ids.country_place_id("no", area.tier, area.naturvern_id)
    county = rules.COUNTIES.get(subdivisions[0].removeprefix("NO-"), "")
    place_id = registry.resolve(
        f"naturvern:{area.naturvern_id}",
        proposed,
        qualifier=ids.romanised_slug(county) if county else None,
    )
    facts: dict[str, Any] = {}
    if year := rules.established_year(area.properties):
        facts["establishedYear"] = year
    if area.area_m2 > 0:
        facts["areaHectares"] = round(area.area_m2 / 10_000)
    place: dict[str, Any] = {
        "id": place_id,
        "name": name,
        "designation": designation,
        "kind": kind,
        "agency": AGENCY,
        "country": COUNTRY,
        "subdivisions": subdivisions,
        "centre": _centre(area),
        "facts": facts,
        "passportRegion": region,
    }
    if fact_sheet := area.properties.get("faktaark"):
        place["officialURL"] = fact_sheet
    if manager := clean(area.properties.get("forvaltningsmyndighet")):
        place["managedBy"] = manager
    item = wiki.match(
        area.naturvern_id, name, area.centre, sources.index, sources.candidates
    )
    summary = sources.summaries.get(area.naturvern_id) if item else None
    if summary and summary.get("type") != "disambiguation" and summary.get("extract"):
        page = ((summary.get("content_urls") or {}).get("desktop") or {}).get("page")
        place["summary"] = wiki.lead(summary["extract"])
        place["summarySource"] = "Wikipedia"
        place["summaryLicence"] = wiki.LICENCE
        if page:
            place["summaryURL"] = page
            place["infoURL"] = page
    if item and (image := _linked_image(wiki.file_name(item.get("image")), sources)):
        place["image"] = image
    return place


def _report_reserves(naturvern_dir: Path, areas: dict[str, Area]) -> None:
    reserves = [area.area_m2 for area in areas.values() if area.tier == "nr"]
    counts = rules.threshold_counts(reserves)
    total = _json(naturvern_dir, "counts.json").get("reserves")
    listed = ", ".join(f"{count} of ≥{km2} km²" for km2, count in counts.items())
    print(f"    nature reserves: {total or '?'} in Norway; {listed}")


# MARK: - Restrictions


def _report_restrictions(areas: dict[str, Area]) -> None:
    """Which parks have traffic, landing and low-flying bans inside them. Fetched for the
    guide writers' "How this park works" panel; the app has no field for them, so they
    are reported rather than shipped."""
    directory = rawstore.latest(RESTRICTIONS)
    if directory is None:
        return
    by_kind: dict[str, set[str]] = {}
    traffic: list[str] = []
    for park, area in national_parks(areas):
        path = directory / "parks" / f"{park['id']}.json"
        if area is None or not path.exists():
            continue
        for feature in json.loads(path.read_text()).get("features") or []:
            properties = feature.get("properties") or {}
            polygons = outline.polygons_of(feature.get("geometry"))
            if not _meets(area, polygons):
                continue
            kind = properties.get("_layer") or "?"
            by_kind.setdefault(kind, set()).add(park["id"])
            if kind == "ferdselsforbud":
                text = clean(properties.get("restriksjonerBeskrivelse")) or ""
                traffic.append(f"{park['name']}: {text}")
    counts = ", ".join(f"{kind} in {len(parks)} parks" for kind, parks in sorted(by_kind.items()))
    print(f"    restriction zones inside national parks: {counts or 'none'}")
    for line in sorted(set(traffic))[:40]:
        print(f"      {line}")


def _meets(area: Area, polygons: list[Any]) -> bool:
    """Whether a restriction zone lies at least partly inside the park: one of its
    corners inside the park, or the park's centre inside it."""
    for polygon in polygons:
        ring = polygon[0] if polygon else []
        step = max(1, len(ring) // 50)
        if any(_inside(area, lon, lat) for lon, lat in ring[::step]):
            return True
    centre = area.centre
    return bool(centre and outline.contains(polygons, centre[1], centre[0]))


# MARK: - Transport


def _transport(areas: dict[str, Area], sources: _Sources) -> dict[str, list[Any]] | None:
    """``railLines`` and ``railStations``, or nothing if OpenStreetMap was not fetched."""
    if sources.osm is None or not list(sources.osm.glob("rail-routes-*.json")):
        print(f"    no raw/{OSM} rail routes: no rail layers this run")
        return None
    counties = sources.fine_counties

    def in_norway(latitude: float, longitude: float) -> bool:
        return counties is None or counties.at(latitude, longitude) is not None

    routes = transport.read_routes(sources.osm)
    lines, belongs = transport.build_lines(routes, in_norway)
    payloads = sources.osm_payloads
    stop_areas = transport.stop_areas(payloads)
    mainland = [
        area
        for park, area in national_parks(areas)
        if area is not None and not park.get("svalbard")
    ]
    reach = [
        (area, box.buffered(transport.STATION_REACH_KM * 1000))
        for area in mainland
        if (box := area.box) is not None
    ]
    stations = []
    without_lines = 0
    for station in transport.stations(payloads):
        point = transport.point_of(station)
        assert point is not None
        if not in_norway(*point):
            continue
        near = any(
            _within(box, point)
            and transport.distance_to_outline_km(point, _coarse(area))
            <= transport.STATION_REACH_KM
            for area, box in reach
        )
        if not near:
            continue
        names = transport.station_lines(station, routes, belongs, stop_areas)
        # A halt no line stops at is a museum line's, or out of use.
        if not names and (station.get("tags") or {}).get("railway") == "halt":
            continue
        without_lines += not names
        stations.append(transport.station_entry(station, names))
    print(
        f"    rail: {len(lines)} passenger lines from {len(belongs)} routes; "
        f"{len(stations)} stations within {transport.STATION_REACH_KM:.0f} km of a park "
        f"({without_lines} with no line recorded)"
    )
    return {"railLines": lines, "railStations": stations}


def _within(box: geo.BoundingBox, point: tuple[float, float]) -> bool:
    latitude, longitude = point
    return box.south <= latitude <= box.north and box.west <= longitude <= box.east


_COARSE: dict[str, list[Any]] = {}


def _coarse(area: Area) -> list[Any]:
    """The park's outline generalised to about 500 m, for distances in kilometres."""
    if area.naturvern_id not in _COARSE:
        _COARSE[area.naturvern_id] = outline.generalise(area.polygons, 0.005) or area.polygons
    return _COARSE[area.naturvern_id]


# MARK: - Documents


def _document_kind(title: str, url: str) -> str:
    text = f"{title} {url.rsplit('/', 1)[-1]}".lower()
    if "kart" in text or "map" in text:
        return "map"
    if any(word in text for word in ("brosjyre", "brochure", "folder", "leaflet", "faktaark")):
        return "brochure"
    return "other"


def _documents(places: list[dict[str, Any]], sources: _Sources) -> dict[str, Any] | None:
    """Each national park's page on norgesnasjonalparker.no — English where the site has
    it — and the PDFs it links that answered."""
    if not sources.documents:
        return None
    result: dict[str, Any] = {}
    for place in places:
        entry = sources.documents.get(place["id"])
        if place["kind"] != "nationalPark" or not entry:
            continue
        documents = []
        for document in entry.get("documents") or []:
            item = {**document, "kind": _document_kind(document["title"], document["url"])}
            documents.append(item)
        rank = {"brochure": 0, "map": 1, "other": 2}
        documents.sort(key=lambda doc: rank[doc["kind"]])
        result[place["id"]] = {
            "page": entry.get("english") or entry.get("page"),
            "documents": documents,
        }
    with_pdf = sum(1 for entry in result.values() if entry["documents"])
    print(f"    documents: {len(result)} park pages, {with_pdf} with a PDF")
    return result
