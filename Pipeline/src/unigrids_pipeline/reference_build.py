"""Build the reference dataset the app bundles, from the raw store and ``content/``.

Writes, into ``UnigridsReference/Resources/reference/``:

``manifest.json``     what this dataset is, when it was built, and from what
``places.json``       national parks, other NPS units, state parks and federal sites
``pois.json``         sights, visitor centres, stamp locations and campgrounds
``themes.json``       theme tags
``guides/np-*.json``  one Unigrid guide per national park
``boundaries.json``   every outline, as encoded polylines
``boundaries-overview.json``  the same outlines generalised for country scale
``routes.json``       every scenic byway's line (``lands_build``)
``transport.json``    Interstates, US routes, Amtrak routes and stations (``lands_build``)
``trails.json``       every national park trail, measured (``trail_catalogue``)
``brochures.json``    each NPS unit's official PDFs and maps page (``brochures``)
``climate.json``      monthly climate at each national park (``climate``)
``images/``           each national park's photographs, resized

The split of responsibility is the one ``content/README.md`` describes: the NPS API says
what the NPS publishes — names, descriptions, fees, hours, visitor centres, photographs —
and the curated files say what Unigrids wrote or chose. Nothing here invents a figure. A
value the sources do not carry is left out, and the app renders it as absent.
"""

from __future__ import annotations

import html
import json
import re
import shutil
import subprocess
from datetime import date
from pathlib import Path
from typing import Any

from timezonefinder import TimezoneFinder

from . import (
    brochures,
    climate,
    config,
    ids,
    lands_build,
    outline,
    park_elevation,
    rawstore,
    reference_content,
    state_parks,
    trail_catalogue,
    visitation,
    wikipedia_match,
)
from .reference_fetch import photo_filename

OUT = config.REPO_ROOT / "Packages/UnigridsKit/Sources/UnigridsReference/Resources/reference"

# Source key → place identifier, committed so an identifier outlives a renamed record
# (``ids.Registry``). National parks, NPS units and curated sites key on their own stable
# codes and do not need it.
PLACE_REGISTRY = config.CONTENT_DIR / "ids" / "places.json"

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

# NPS API designations that are not NPS-managed places a visitor goes to: partnership
# areas, and trails that cross half a continent and have no single pin to drop.
EXCLUDED_DESIGNATIONS = re.compile(
    r"heritage|affiliated|trail|partnership|international park", re.IGNORECASE
)

# NPS API records that are offices, umbrella units or partnerships rather than places:
# their parts are listed separately, or there is nowhere to visit.
ADMINISTRATIVE_UNITS = frozenset({
    "CBPO", "ANCH", "NPNH", "NACE", "MAAC", "INUP", "HAHA", "GRSP", "GREG", "NAMA", "CAHI",
    "PAAV",
})

# Lead-image licences that allow reuse with credit. Anything else is left out.
REUSABLE_LICENCE = re.compile(r"^(public domain|pd|cc0|cc by(-sa)? \d)", re.IGNORECASE)


def build(*, online: bool = False) -> None:
    """Build the dataset. ``online`` lets the build fetch what it can only know once the
    places exist — Wikipedia articles for the ones without prose — into the raw store;
    offline, it reads what an earlier run cached."""
    raw = _latest_raw("nps-api")
    print(f"    reading raw/{raw.name}")
    api = _NPSData(raw / "nps-api")
    unit_outlines = _unit_outlines(_latest_raw("unit-boundaries") / "unit-boundaries")
    padus, padus_acres = _padus_outlines(rawstore.require("padus", "curated.geojson"))
    wikipedia = _wikipedia(_latest_raw("wikipedia") / "wikipedia")
    photos_dir = _latest_raw_or_none("photos")
    registry = ids.Registry(PLACE_REGISTRY)

    # Photographs are rebuilt in place rather than wiped: a resized copy whose raw original
    # has since been cleared from the raw store (they are large) is kept as it is.
    images_dir = OUT / "images"
    images_dir.mkdir(parents=True, exist_ok=True)
    written_images: set[str] = set()
    guides_dir = OUT / "guides"
    if guides_dir.exists():
        shutil.rmtree(guides_dir)
    guides_dir.mkdir(parents=True)

    places: list[dict[str, Any]] = []
    pois: list[dict[str, Any]] = []
    boundaries: dict[str, Any] = {}
    guides: dict[str, dict[str, Any]] = {}
    national_codes = set()

    facts = reference_content.national_park_facts()
    for code, row in reference_content.national_park_rows():
        national_codes.add(code)
        place, guide, park_pois = _national_park(
            row,
            api.parks.get(reference_content.api_code(row)),
            facts.get(row["id"], {}),
            api,
            photos_dir,
            images_dir,
            unit_outlines.get(code),
        )
        written_images.update(
            image["assetName"]
            for image in [guide.get("hero"), *guide.get("gallery", [])]
            if image and image.get("assetName")
        )
        outline_entry = _encode_outline(unit_outlines.get(code), NATIONAL_PARK_TOLERANCE)
        if outline_entry:
            boundaries[place["id"]] = outline_entry
            place["extent"] = _extent(outline_entry["bbox"])
        places.append(place)
        pois.extend(park_pois)
        guides[place["id"]] = guide

    api_national_codes = {
        reference_content.api_code(row) for _, row in reference_content.national_park_rows()
    }
    for code, park in sorted(api.parks.items()):
        if code in national_codes or code in api_national_codes or code in ADMINISTRATIVE_UNITS:
            continue
        if EXCLUDED_DESIGNATIONS.search(park.get("designation") or ""):
            continue
        place, unit_pois = _nps_unit(park, api)
        outline_entry = _encode_outline(unit_outlines.get(code), OTHER_TOLERANCE)
        if outline_entry:
            boundaries[place["id"]] = outline_entry
            place["extent"] = _extent(outline_entry["bbox"])
        if place["centre"] is None:
            if not outline_entry:
                continue
            south, west, north, east = outline_entry["bbox"]
            place["centre"] = {"latitude": (south + north) / 2, "longitude": (west + east) / 2}
        if not place["states"]:
            continue
        places.append(place)
        pois.extend(unit_pois)

    curated_ids = {site["id"] for site in reference_content.curated_sites()}
    for site in reference_content.curated_sites():
        key = site["id"]
        polygons = padus.get(key)
        if not polygons:
            print(f"    skipped {site['id']}: no PAD-US outline")
            continue
        place, outline_entry = _curated_site(
            site, polygons, padus_acres.get(key), wikipedia.get(site["id"])
        )
        boundaries[place["id"]] = outline_entry
        places.append(place)

    census = rawstore.latest("padus", state_parks.FILE)
    if census is not None:
        state_parks.build(
            census, places, boundaries, registry, reference_content.curated_sites()
        )

    routes: dict[str, Any] = {}
    lands = _latest_raw_or_none("federal-lands")
    if lands is not None:
        routes = lands_build.build(lands, places, boundaries, registry)
    transport_dir = _latest_raw_or_none("transport")
    transport = lands_build.build_transport(transport_dir) if transport_dir else None
    trails_dir = _latest_raw_or_none("trails-national")
    catalogue = trail_catalogue.build(trails_dir, unit_outlines, pois) if trails_dir else None
    brochures_dir = _latest_raw_or_none("brochures")
    documents = brochures.build(brochures_dir, places) if brochures_dir else None
    climate_dir = _latest_raw_or_none("climate")
    normals = climate.build(climate_dir) if climate_dir else None

    pois.extend(_stamp_locations(places, pois, api))
    visitation.attach(places, visitation.build(rawstore.latest(visitation.SOURCE, visitation.FILE)))
    park_elevation.attach(places, rawstore.latest(park_elevation.SOURCE, park_elevation.FILE))
    _assign_time_zones(places)

    if online:
        wikipedia_match.fetch(places, rawstore.today())
    wikipedia_match.enrich(
        places,
        boundaries,
        routes,
        rawstore.latest(wikipedia_match.SOURCE, wikipedia_match.PAGES_FILE),
        _wikimedia_image,
    )

    for stale in images_dir.iterdir():
        if stale.name not in written_images:
            stale.unlink()

    _write("manifest", _manifest(places))
    _write("places", places)
    _write("pois", pois)
    _write("themes", reference_content.themes())
    _write("boundaries", boundaries, compact=True)
    _write("boundaries-overview", _overview_outlines(boundaries), compact=True)
    _write("routes", routes, compact=True)
    if transport is not None:
        _write("transport", transport, compact=True)
    if catalogue is not None:
        _write("trails", catalogue, compact=True)
    if documents is not None:
        _write("brochures", documents, compact=True)
    if normals is not None:
        _write("climate", normals, compact=True)
    for place_id, guide in guides.items():
        _write(f"guides/{place_id}", guide)
    registry.save()
    if registry.added:
        print(f"    identifiers: {registry.added} new, recorded in {PLACE_REGISTRY.name}")

    image_bytes = sum(path.stat().st_size for path in images_dir.iterdir())
    outline_bytes = (OUT / "boundaries.json").stat().st_size
    tiers: dict[str, int] = {}
    for place in places:
        tiers[place["kind"]] = tiers.get(place["kind"], 0) + 1
    print(f"    places: {len(places)} {tiers}")
    print(f"    points of interest: {len(pois)}")
    print(f"    outlines: {len(boundaries)}, {outline_bytes / 1e6:.2f} MB")
    print(f"    photographs: {len(list(images_dir.iterdir()))}, {image_bytes / 1e6:.1f} MB")
    written = sum(1 for guide in guides.values() if guide.get("story"))
    print(f"    guides with written content: {written} of {len(guides)}")
    # The other public lands carry no prose by design (lands_build); only an NPS unit or
    # a curated site without one is worth reporting.
    unwritten = [
        place["id"]
        for place in places
        if place.get("summary") is None
        and (place["kind"] in ("nationalPark", "npsUnit") or place["id"] in curated_ids)
    ]
    if unwritten:
        print(f"    places without a summary: {', '.join(unwritten)}")


# MARK: - National parks


def _national_park(
    row: dict[str, Any],
    park: dict[str, Any] | None,
    facts: dict[str, Any],
    api: _NPSData,
    photos_dir: Path | None,
    images_dir: Path,
    polygons: list[outline.Polygon] | None,
) -> tuple[dict[str, Any], dict[str, Any], list[dict[str, Any]]]:
    place_id, slug, code = row["id"], row["slug"], row["npsParkCode"]
    api_code = reference_content.api_code(row)
    content = reference_content.guide(place_id) or {}
    park = park or {}

    def mine(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
        """A shared API record's rows that fall inside this park's own outline."""
        if api_code == code or not polygons:
            return rows
        return [
            r for r in rows
            if (c := _coordinate(r)) and outline.contains(polygons, c["longitude"], c["latitude"])
        ]

    photos = reference_content.choose_photos(
        park.get("images") or [],
        keywords=row.get("photoKeywords"),
        skip=row.get("photoSkip"),
        captions=row.get("photoCaptions"),
    )
    # A curated hero, where the NPS's own record has no photograph Unigrids may reuse.
    if override := content.get("heroOverride"):
        photos = [override, *photos]
    hero, gallery = None, []
    for image in photos:
        if len(gallery) == GALLERY_COUNT:
            break
        source = photos_dir / photo_filename(image["url"]) if photos_dir else None
        index = 1 + (0 if hero is None else 1 + len(gallery))
        name = f"{place_id}-{index}.jpg"
        size, quality = (HERO_SIZE, HERO_QUALITY) if hero is None else (
            GALLERY_SIZE, GALLERY_QUALITY
        )
        # A photograph already resized is left alone: rewriting identical bytes on every
        # build churns a synced checkout, and iCloud answers churn with conflict copies.
        if (images_dir / name).exists():
            pass
        elif source is not None and source.exists():
            if not _resize(source, images_dir / name, size, quality):
                continue
        elif not (images_dir / name).exists():
            continue
        entry = _guide_image(image, asset_name=name)
        if hero is None:
            hero = entry
        else:
            gallery.append(entry)

    place_facts = dict(content.get("facts") or {})
    if facts:
        place_facts["establishedYear"] = int(facts["established"][:4])
        place_facts["areaAcres"] = facts["areaAcres"]
        place_facts["annualVisits"] = facts["annualVisits"]
        place_facts["annualVisitsYear"] = facts["annualVisitsYear"]
    fees = _fees(park)
    fees_passes = api.fees_passes.get(api_code, {})
    fees = _with_free_entry(fees, fees_passes)
    if fee := _fee_summary(fees):
        place_facts.setdefault("entranceFee", fee)

    centre = _coordinate(park) or {"latitude": row["centre"][0], "longitude": row["centre"][1]}
    summary = content.get("summary")
    official = park.get("url") or f"https://www.nps.gov/{code.lower()}/"
    place = {
        "id": place_id,
        "name": row["name"],
        "designation": row["designation"],
        "kind": "nationalPark",
        "agency": "nps",
        "states": row["states"],
        "centre": centre,
        "npsParkCode": code,
        "themes": row["themes"],
        "facts": place_facts,
        "officialURL": official,
        "summary": summary or _clean(park.get("description")),
        "summarySource": "Unigrids" if summary else "National Park Service",
    }
    if activities := _activities(park):
        place["activities"] = activities
    if hero:
        place["image"] = hero

    pois = _sights(slug, place_id, content, mine(api.places_for(api_code)))
    pois.extend(
        _visitor_centres(slug, place_id, mine(api.visitor_centres_for(api_code)), api, api_code)
    )
    pois.extend(_campgrounds(slug, place_id, mine(api.campgrounds_for(api_code))))

    sources = [*content.get("sources", [])]
    if not any("nps.gov" in (source.get("url") or "") for source in sources):
        sources.append({"title": f"{row['name']} — National Park Service", "url": official})
    plan = dict(content.get("planYourVisit") or {})
    if not plan.get("reservations") and (timed := _timed_entry(fees_passes)):
        plan["reservations"] = timed
    if not plan.get("camping"):
        plan["camping"] = _camping_lines(mine(api.campgrounds_for(api_code)))

    guide: dict[str, Any] = {
        "placeID": place_id,
        "contentVersion": content.get("contentVersion", 1),
        "story": content.get("story", []),
        "sightNotes": {
            poi["id"]: poi["summary"]
            for poi in pois
            if poi["kind"] in ("sight", "viewpoint") and poi.get("summary")
        },
        "planYourVisit": {key: value for key, value in plan.items() if value},
        "chronology": content.get("chronology", []),
        "safety": content.get("safety", []),
        "regulations": content.get("regulations", []),
        "credits": content.get("credits") or [
            "Text written for Unigrids from public-domain National Park Service material. "
            "Fees, hours, weather and directions notes are the NPS's own."
        ],
        "sources": sources,
        "fees": fees,
    }
    if hero:
        guide["hero"] = hero
    if gallery:
        guide["gallery"] = gallery
    for key, field in (
        ("operatingHours", _hours_note(park)),
        ("weather", _clean(park.get("weatherInfo"))),
        ("directions", _clean(park.get("directionsInfo"))),
    ):
        if field:
            guide[key] = field
    return place, guide, pois


def _sights(
    slug: str, place_id: str, content: dict[str, Any], places: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    """The guide's ranked sights: Unigrids chooses them, the NPS places them."""
    by_title = {_normal(place.get("title") or ""): place for place in places}
    result = []
    for rank, sight in enumerate(content.get("sights", []), start=1):
        match = by_title.get(_normal(sight.get("match") or sight["name"]))
        # The NPS's own coordinate wins; a hand-placed one is the fallback for a sight
        # the NPS has no place record for.
        location = _coordinate(match) if match else None
        if location is None and sight.get("location"):
            latitude, longitude = sight["location"]
            location = {"latitude": latitude, "longitude": longitude}
        if location is None:
            print(f"    {place_id}: no location for sight {sight['name']!r}, left out")
            continue
        poi: dict[str, Any] = {
            "id": ids.poi_id(slug, sight["name"]),
            "placeID": place_id,
            "kind": sight.get("kind", "sight"),
            "name": sight["name"],
            "location": location,
            "rank": rank,
            "summary": sight.get("note")
            or _without_notices(_clean((match or {}).get("listingDescription"))),
            "hasStamp": False,
        }
        if match:
            photo = reference_content.choose_photos(match.get("images") or [], limit=1)
            if photo:
                poi["image"] = _guide_image(photo[0])
            if match.get("url"):
                poi["url"] = match["url"]
        result.append(poi)
    return result


def _visitor_centres(
    slug: str, place_id: str, centres: list[dict[str, Any]], api: _NPSData, code: str
) -> list[dict[str, Any]]:
    stamps = api.stamp_labels_for(code)
    result = []
    seen = set()
    for centre in sorted(centres, key=lambda c: c.get("name") or ""):
        location = _coordinate(centre)
        name = (centre.get("name") or "").strip()
        poi_id = ids.poi_id(slug, name)
        if not location or not name or poi_id in seen:
            continue
        seen.add(poi_id)
        normal = _normal(name)
        has_stamp = str(centre.get("isPassportStampLocation")).lower() in ("1", "true") or any(
            label and (normal in label or label in normal) for label in stamps
        )
        poi: dict[str, Any] = {
            "id": poi_id,
            "placeID": place_id,
            "kind": "visitorCentre",
            "name": name,
            "location": location,
            "rank": 0,
            "summary": _first_sentences(_without_notices(_clean(centre.get("description"))), 2),
            "hasStamp": has_stamp,
        }
        if hours := _hours_line(centre):
            poi["hours"] = hours
        if centre.get("url"):
            poi["url"] = centre["url"]
        result.append(poi)
    return result


def _campgrounds(slug: str, place_id: str, camps: list[dict[str, Any]]) -> list[dict[str, Any]]:
    result = []
    seen = set()
    for camp in camps:
        location = _coordinate(camp)
        name = (camp.get("name") or "").strip()
        poi_id = ids.poi_id(slug, name)
        if not location or not name or poi_id in seen:
            continue
        seen.add(poi_id)
        result.append({
            "id": poi_id,
            "placeID": place_id,
            "kind": "campground",
            "name": name,
            "location": location,
            "rank": 0,
            "summary": _first_sentences(_without_notices(_clean(camp.get("description"))), 1),
            "hasStamp": False,
        })
    return result


def _camping_lines(camps: list[dict[str, Any]]) -> list[str]:
    lines = []
    for camp in sorted(camps, key=lambda c: c.get("name") or ""):
        name = (camp.get("name") or "").strip()
        if not name:
            continue
        reservable = int(_number(camp.get("numberOfSitesReservable")) or 0)
        first_come = int(_number(camp.get("numberOfSitesFirstComeFirstServe")) or 0)
        if reservable and first_come:
            note = "reservable, with some first-come sites"
        elif reservable:
            note = "reservable"
        elif first_come:
            note = "first come, first served"
        else:
            note = ""
        lines.append(f"{name}, {note}" if note else name)
    return lines


# MARK: - Other NPS units


def _nps_unit(park: dict[str, Any], api: _NPSData) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    code = park["parkCode"].upper()
    place_id = f"nps-{code.lower()}"
    states = [state.strip() for state in (park.get("states") or "").split(",") if state.strip()]
    photo = reference_content.choose_photos(park.get("images") or [], limit=1)
    facts: dict[str, Any] = {}
    unit_fees = _with_free_entry(_fees(park), api.fees_passes.get(code, {}))
    if fee := _fee_summary(unit_fees):
        facts["entranceFee"] = fee
    place: dict[str, Any] = {
        "id": place_id,
        "name": _clean(park.get("name")) or _clean(park.get("fullName")),
        "designation": _clean(park.get("designation")) or _designation_from_name(park),
        "kind": "npsUnit",
        "agency": "nps",
        "states": states,
        "centre": _coordinate(park),
        "npsParkCode": code,
        "facts": facts,
        "officialURL": park.get("url"),
        "summary": _clean(park.get("description")),
        "summarySource": "National Park Service",
    }
    if activities := _activities(park):
        place["activities"] = activities
    if photo:
        place["image"] = _guide_image(photo[0])
    if info := _visitor_info(park, api.fees_passes.get(code, {})):
        place["visitorInfo"] = info
    pois = _visitor_centres(code.lower(), place_id, api.visitor_centres_for(code), api, code)
    return place, pois


def _visitor_info(park: dict[str, Any], fees_passes: dict[str, Any]) -> dict[str, Any]:
    """What a visitor needs before going to an NPS unit, as the NPS publishes it — the
    same fields a national park's guide carries in Plan your visit and Getting there."""
    info: dict[str, Any] = {}
    if fees := _with_free_entry(_fees(park), fees_passes):
        info["fees"] = fees
    if timed := _timed_entry(fees_passes):
        info["reservations"] = timed
    for key, field in (
        ("operatingHours", _hours_note(park)),
        ("directions", _clean(park.get("directionsInfo"))),
        ("weather", _clean(park.get("weatherInfo"))),
    ):
        if field:
            info[key] = field
    contacts = park.get("contacts") or {}
    phones = [
        (entry.get("phoneNumber") or "").strip()
        for entry in contacts.get("phoneNumbers") or []
        if (entry.get("type") or "").lower() == "voice"
    ]
    if phone := next((number for number in phones if number), None):
        info["phone"] = phone
    emails = [
        (entry.get("emailAddress") or "").strip()
        for entry in contacts.get("emailAddresses") or []
    ]
    if email := next((address for address in emails if "@" in address), None):
        info["email"] = email
    return info


# The NPS Data API's activity names, folded into the dozen the map can filter on
# (``UnigridsCore.PlaceActivity``). An activity not listed here is not offered as a filter.
ACTIVITY_GROUPS: dict[str, tuple[str, ...]] = {
    "hiking": ("Hiking", "Front-Country Hiking", "Backcountry Hiking"),
    "camping": (
        "Camping", "Backcountry Camping", "Car or Front Country Camping", "RV Camping",
        "Group Camping", "Canoe or Kayak Camping", "Horse Camping",
    ),
    "scenicDriving": ("Scenic Driving", "Self-Guided Tours - Auto"),
    "wildlifeWatching": ("Wildlife Watching", "Birdwatching"),
    "paddling": (
        "Paddling", "Kayaking", "Canoeing", "Boating", "Stand Up Paddleboarding",
        "Motorized Boating", "Sailing", "Boat Tour",
    ),
    "fishing": ("Fishing", "Freshwater Fishing", "Saltwater Fishing", "Fly Fishing"),
    "stargazing": ("Astronomy", "Stargazing"),
    "biking": ("Biking", "Road Biking", "Mountain Biking"),
    "swimming": ("Swimming", "Freshwater Swimming", "Saltwater Swimming"),
    "winterSports": (
        "Skiing", "Snowshoeing", "Cross-Country Skiing", "Downhill Skiing", "Snowmobiling",
        "Ice Skating",
    ),
    "climbing": ("Climbing", "Rock Climbing", "Mountain Climbing", "Ice Climbing"),
    "museums": ("Museum Exhibits", "Living History"),
}


def _activities(park: dict[str, Any]) -> list[str]:
    named = {(activity.get("name") or "").strip() for activity in park.get("activities") or []}
    return [group for group, names in ACTIVITY_GROUPS.items() if named.intersection(names)]


def _designation_from_name(park: dict[str, Any]) -> str:
    """A designation for the units the API leaves blank — the memorials on the Mall,
    Alcatraz — read off the end of their own names rather than invented."""
    full = _clean(park.get("fullName")) or ""
    for word in ("Memorial", "Park", "Island", "Monument"):
        if full.endswith(word):
            return word if word != "Island" else "National Park Service site"
    return "National Park Service site"


# MARK: - State parks and other agencies


def _curated_site(
    site: dict[str, Any],
    polygons: list[outline.Polygon],
    acres: float | None,
    wiki: dict[str, Any] | None,
) -> tuple[dict[str, Any], dict[str, Any]]:
    outline_entry = _encode_outline(polygons, OTHER_TOLERANCE)
    assert outline_entry is not None
    latitude, longitude = outline.label_point(polygons) or (0.0, 0.0)
    place: dict[str, Any] = {
        "id": site["id"],
        "name": site["name"],
        "designation": site["designation"],
        "kind": site["kind"],
        "agency": site["agency"],
        "states": site["states"],
        "centre": {"latitude": round(latitude, 5), "longitude": round(longitude, 5)},
        "extent": _extent(outline_entry["bbox"]),
        "themes": site.get("themes", []),
        "facts": {"areaAcres": round(acres)} if acres else {},
        "summary": site.get("summary"),
        "summarySource": "Unigrids",
    }
    if site.get("officialURL"):
        place["officialURL"] = site["officialURL"]
    if wiki:
        page = ((wiki.get("content_urls") or {}).get("desktop") or {}).get("page")
        if page:
            place["infoURL"] = page
        image = _wikimedia_image(wiki.get("_licence"))
        if image:
            place["image"] = image
    return place, outline_entry


def _wikimedia_image(licence: dict[str, Any] | None) -> dict[str, Any] | None:
    if not licence or not licence.get("thumbURL"):
        return None
    name = (licence.get("licence") or "").strip()
    if not REUSABLE_LICENCE.search(name):
        return None
    artist = _strip_tags(licence.get("artist") or "") or "Unknown photographer"
    public = name.lower().startswith(("public domain", "pd", "cc0"))
    image = {
        "url": licence["thumbURL"],
        "credit": f"{artist}, via Wikimedia Commons",
        "isPublicDomain": public,
        "sourceURL": licence.get("descriptionURL"),
    }
    if not public:
        image["licence"] = name
    return image


# MARK: - Stamp locations


def _stamp_locations(
    places: list[dict[str, Any]], pois: list[dict[str, Any]], api: _NPSData
) -> list[dict[str, Any]]:
    """A point of interest for every passport stamp location no visitor centre stands for.

    The NPS lists a site's cancellations by label and type, with no coordinates. A label
    that names one of the site's visitor centres is that centre's stamp (``hasStamp``);
    every other one — a stamp kept at a ranger station, a museum, a fort — becomes a
    ``stampLocation`` at the site's own centre, so the passport has a slot for it. Those
    are for the passport only: no map draws a stamp location, because its position is
    the site's, not its own.
    """
    by_place: dict[str, list[dict[str, Any]]] = {}
    for poi in pois:
        by_place.setdefault(poi["placeID"], []).append(poi)
    added: list[dict[str, Any]] = []
    for place in places:
        code = place.get("npsParkCode")
        if not code:
            continue
        rows = api.stamp_rows_for(code)
        if not rows:
            continue
        slug = place["id"].split("-", 1)[1] if "-" in place["id"] else place["id"]
        stamped = {
            _normal(poi["name"]) for poi in by_place.get(place["id"], []) if poi.get("hasStamp")
        }
        seen: set[str] = set()
        for row in rows:
            label = _stamp_label(row.get("label") or "")
            normal = _normal(label)
            if not normal or normal in seen:
                continue
            seen.add(normal)
            if any(normal in name or name in normal for name in stamped):
                continue
            added.append({
                "id": ids.poi_id(slug, f"stamp {label}"),
                "placeID": place["id"],
                "kind": "stampLocation",
                "name": label,
                "location": place["centre"],
                "rank": 0,
                "hasStamp": True,
            })
    print(f"    stamp locations: {len(added)} beside the visitor centres that keep one")
    return added


def _stamp_label(raw: str) -> str:
    """A stamp location's name without a status that will go stale: "(Temporarily
    Closed)", "- Closed for Renovation"."""
    label = re.sub(r"\s*\((?:[^)]*clos[^)]*)\)", "", raw, flags=re.IGNORECASE)
    label = re.sub(r"\s*[-–]\s*clos.*$", "", label, flags=re.IGNORECASE)
    return re.sub(r"\s+", " ", label).strip()


# MARK: - Time zones


def _assign_time_zones(places: list[dict[str, Any]]) -> None:
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


# MARK: - Raw data


class _NPSData:
    def __init__(self, directory: Path) -> None:
        def load(name: str) -> list[dict[str, Any]]:
            path = directory / f"{name}.json"
            return json.loads(path.read_text()) if path.exists() else []

        self.parks = {row["parkCode"].upper(): row for row in load("parks")}
        self.fees_passes = {
            (row.get("parkCode") or "").upper(): row for row in load("feespasses")
        }
        self._centres = _group(load("visitorcenters"), "parkCode")
        self._places = _group_related(load("places"))
        self._camps = _group(load("campgrounds"), "parkCode")
        self._stamps: dict[str, list[str]] = {}
        self._stamp_rows: dict[str, list[dict[str, Any]]] = {}
        for stamp in load("passportstamplocations"):
            label = _normal(stamp.get("label") or "")
            for related in stamp.get("parks") or []:
                code = (related.get("parkCode") or "").upper()
                self._stamps.setdefault(code, []).append(label)
                self._stamp_rows.setdefault(code, []).append(stamp)

    def visitor_centres_for(self, code: str) -> list[dict[str, Any]]:
        return self._centres.get(code, [])

    def places_for(self, code: str) -> list[dict[str, Any]]:
        return self._places.get(code, [])

    def campgrounds_for(self, code: str) -> list[dict[str, Any]]:
        return self._camps.get(code, [])

    def stamp_labels_for(self, code: str) -> list[str]:
        return [label for label in self._stamps.get(code, []) if label]

    def stamp_rows_for(self, code: str) -> list[dict[str, Any]]:
        return self._stamp_rows.get(code, [])


def _group(rows: list[dict[str, Any]], key: str) -> dict[str, list[dict[str, Any]]]:
    grouped: dict[str, list[dict[str, Any]]] = {}
    for row in rows:
        grouped.setdefault((row.get(key) or "").upper(), []).append(row)
    return grouped


def _group_related(rows: list[dict[str, Any]]) -> dict[str, list[dict[str, Any]]]:
    grouped: dict[str, list[dict[str, Any]]] = {}
    for row in rows:
        for related in row.get("relatedParks") or []:
            grouped.setdefault((related.get("parkCode") or "").upper(), []).append(row)
    return grouped


def _unit_outlines(directory: Path) -> dict[str, list[outline.Polygon]]:
    payload = json.loads((directory / "nps-units.geojson").read_text())
    result: dict[str, list[outline.Polygon]] = {}
    for feature in payload["features"]:
        code = ((feature.get("properties") or {}).get("UNIT_CODE") or "").upper()
        result.setdefault(code, []).extend(outline.polygons_of(feature.get("geometry")))
    return result


def _padus_outlines(
    directory: Path,
) -> tuple[dict[str, list[outline.Polygon]], dict[str, float]]:
    payload = json.loads((directory / "curated.geojson").read_text())
    result: dict[tuple[str, str], list[outline.Polygon]] = {}
    areas: dict[tuple[str, str], float] = {}
    for feature in payload["features"]:
        properties = feature.get("properties") or {}
        site = properties.get("_site")
        if not site:
            continue
        result.setdefault(site, []).extend(outline.polygons_of(feature.get("geometry")))
        acres = properties.get("GIS_Acres") or properties.get("GIS_AcreD") or 0
        areas[site] = areas.get(site, 0.0) + float(acres)
    return result, areas


def _wikipedia(directory: Path) -> dict[str, Any]:
    path = directory / "summaries.json"
    return json.loads(path.read_text()) if path.exists() else {}


def _latest_raw_or_none(source: str) -> Path | None:
    try:
        return _latest_raw(source) / source
    except SystemExit:
        return None


def _latest_raw(source: str) -> Path:
    candidates = sorted(
        (path for path in config.RAW_DIR.iterdir() if (path / source).is_dir()), reverse=True
    )
    if not candidates:
        raise SystemExit(f"no raw/{source} yet: run `unigrids-pipeline reference` with network")
    return candidates[0]


# MARK: - Field helpers


def _encode_outline(
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


# The country-scale outlines, in degrees: about 900 m. Drawn when the whole Lower 48 is
# on screen, where a pixel is several kilometres, so nothing finer would show; a speck that
# vanishes at this tolerance leaves its pin to stand for it.
OVERVIEW_TOLERANCE = 0.008


def _overview_outlines(boundaries: dict[str, Any]) -> dict[str, Any]:
    """Every outline again, generalised for the map at country scale.

    Fourteen hundred outlines at full detail are a quarter of a million vertices: more
    than the map should draw for a view where none of that detail is visible. This set is
    a tenth of the size, and the map swaps to the full one as the camera comes in.
    """
    overview: dict[str, Any] = {}
    for place_id, entry in boundaries.items():
        polygons = [[outline.decode(ring) for ring in polygon] for polygon in entry["polygons"]]
        coarse = _encode_outline(polygons, OVERVIEW_TOLERANCE)
        if coarse:
            overview[place_id] = coarse
    return overview


def _extent(box: list[float]) -> dict[str, float]:
    south, west, north, east = box
    return {"south": south, "west": west, "north": north, "east": east}


def _coordinate(row: dict[str, Any] | None) -> dict[str, float] | None:
    if not row:
        return None
    latitude, longitude = _number(row.get("latitude")), _number(row.get("longitude"))
    if latitude is None or longitude is None or (latitude == 0 and longitude == 0):
        return None
    return {"latitude": round(latitude, 5), "longitude": round(longitude, 5)}


def _number(value: Any) -> float | None:
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _guide_image(image: dict[str, Any], *, asset_name: str | None = None) -> dict[str, Any]:
    entry: dict[str, Any] = {
        "credit": _clean(image.get("credit")) or "NPS",
        "isPublicDomain": True,
    }
    if asset_name:
        entry["assetName"] = asset_name
    else:
        entry["url"] = image["url"]
    if caption := _clean(image.get("title")):
        entry["caption"] = caption
    if source := image.get("sourceURL"):
        entry["sourceURL"] = source
    if alt := _clean(image.get("altText")):
        entry["altText"] = alt
    return entry


def _fees(park: dict[str, Any]) -> list[dict[str, Any]]:
    fees = []
    for fee in park.get("entranceFees") or []:
        cost = _number(fee.get("cost"))
        raw_title = fee.get("title") or ""
        if cost is None or "commercial" in raw_title.lower():
            continue
        title = re.sub(r"^\s*entrance\s*-\s*", "", raw_title, flags=re.IGNORECASE).strip()
        title = title[:1].upper() + title[1:].lower() if title else "Entrance"
        if cost == 0:
            price = "Free"
        elif cost == int(cost):
            price = f"${cost:,.0f}"
        else:
            price = f"${cost:,.2f}"
        fees.append({"title": title, "cost": price, "detail": _clean(fee.get("description"))})
    return fees


def _fee_summary(fees: list[dict[str, Any]]) -> str | None:
    if len(fees) == 1 and fees[0]["cost"] == "Free":
        return "Free"
    for wanted, phrase in (("vehicle", "per private vehicle"), ("person", "per person")):
        for fee in fees:
            if wanted in fee["title"].lower() and fee["cost"] != "Free":
                return f"{fee['cost']} {phrase}"
    return None


def _with_free_entry(
    fees: list[dict[str, Any]], fees_passes: dict[str, Any]
) -> list[dict[str, Any]]:
    """``fees``, or a single free entry where the NPS says the park charges none.

    "No fee figure" and "free" used to look the same. The NPS's own ``isFeeFreePark``
    tells them apart; its entrance note travels with the row, which is where a park like
    the Smokies explains that a parking tag is not an entrance fee.
    """
    if fees or fees_passes.get("isFeeFreePark") is not True:
        return fees
    return [{
        "title": "Entrance",
        "cost": "Free",
        "detail": _clean(fees_passes.get("entranceFeeDescription")),
    }]


def _timed_entry(fees_passes: dict[str, Any]) -> str | None:
    """The NPS's own timed-entry or reservation note, where it publishes one."""
    heading = _clean(fees_passes.get("timedEntryHeading"))
    body = _without_notices(_clean(fees_passes.get("timedEntryDescription")))
    if not body:
        return None
    return f"{heading}: {body}" if heading and not body.startswith(heading) else body


def _hours_note(park: dict[str, Any]) -> str | None:
    hours = park.get("operatingHours") or []
    return _clean(hours[0].get("description")) if hours else None


def _hours_line(row: dict[str, Any]) -> str | None:
    hours = row.get("operatingHours") or []
    if not hours:
        return None
    standard = hours[0].get("standardHours") or {}
    values = {value for value in standard.values() if value}
    if len(values) == 1 and len(standard) == 7:
        value = values.pop()
        if value.lower() == "closed":
            return "Closed"
        return f"Daily, {value.replace(' - ', '–')}"
    return _first_sentences(_without_notices(_clean(hours[0].get("description"))), 1)


# A sentence that announces a dated opening or closure — "Closed for 2026.", "Scheduled to
# open late October 2026", "open May 9–October 31, 2025" — is true for a season and then
# wrong for good. The bundle outlives the season, so the sentence is left out; live alerts
# carry closures.
_YEAR = r"\b202\d\b"
_OPENING = r"\b(?:clos(?:ed|es|ing|ure)|re-?open(?:s|ed|ing)?|open(?:s|ed|ing)?|scheduled|until)\b"
_DATED_NOTICE = re.compile(
    rf"{_OPENING}[^.!?]*{_YEAR}|{_YEAR}[^.!?]*\b(?:clos(?:ed|es|ing|ure)|re-?open\w*)\b",
    re.IGNORECASE,
)
_SHOUTED = re.compile(r"^[\s*#!]+|[\s*#]+$")


def _without_notices(text: str | None) -> str | None:
    """``text`` without dated opening and closure notices or leading asterisks."""
    if not text:
        return text
    # A notice set off in asterisks ("***CLOSED as of …***") is its own sentence.
    sentences = [
        sentence
        for block in re.split(r"\*{2,}", text)
        for sentence in re.split(r"(?<=[.!?])\s+", block.strip())
    ]
    kept = [
        _SHOUTED.sub("", sentence).strip()
        for sentence in sentences
        if not _DATED_NOTICE.search(sentence) and not re.match(r"^\W*CLOSED\b", sentence)
    ]
    cleaned = " ".join(sentence for sentence in kept if sentence)
    return cleaned or None


_TAG = re.compile(r"<[^>]+>")
_SPACE = re.compile(r"\s+")


def _strip_tags(text: str) -> str:
    return _SPACE.sub(" ", html.unescape(_TAG.sub(" ", text))).strip()


# Characters a source lost in transit, put back where the right text is known. The NPS
# API returns Haleakalā's ʻokina as a question mark in some captions.
TEXT_REPAIRS = {"?Ohe?o": "ʻOheʻo", "Kīpahulu?": "Kīpahulu"}


def _clean(text: Any) -> str | None:
    if not isinstance(text, str):
        return None
    cleaned = _strip_tags(text)
    for damaged, repaired in TEXT_REPAIRS.items():
        cleaned = cleaned.replace(damaged, repaired)
    return cleaned or None


def _first_sentences(text: str | None, count: int) -> str | None:
    if not text:
        return None
    sentences = re.split(r"(?<=[.!?])\s+(?=[A-Z])", text)
    return " ".join(sentences[:count]).strip()


def _normal(text: str) -> str:
    return ids.slug(text).replace("-", " ").strip()


# MARK: - Output


def _resize(source: Path, destination: Path, size: int, quality: int) -> bool:
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


def _manifest(places: list[dict[str, Any]]) -> dict[str, Any]:
    others = sum(1 for place in places if place["kind"] != "nationalPark")
    return {
        "version": 3,
        "builtOn": date.today().isoformat(),
        "provenance": "pipeline",
        "note": (
            f"All 63 national parks with a full guide, and {others} more places on the map: "
            "other NPS units from the NPS Data API; state parks from PAD-US; every national "
            "forest, grassland and wildlife refuge, the BLM's monuments and conservation "
            "areas, National Natural Landmarks and scenic byways from their agencies' own "
            "data. Guide prose is written for Unigrids; descriptions, fees, hours, visitor "
            "centres and photographs are the NPS's own."
        ),
    }


def _write(name: str, payload: Any, *, compact: bool = False) -> None:
    path = OUT / f"{name}.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    if compact:
        text = json.dumps(payload, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
    else:
        text = json.dumps(payload, ensure_ascii=False, indent=1)
    path.write_text(text + "\n")
