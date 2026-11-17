"""The United States' share of the reference dataset.

The national parks with their guides, every other NPS unit, the curated state parks and
federal sites, every state park PAD-US lists, the federal land agencies' lands, and the
transport, trail, document and climate layers.

The split of responsibility is the one ``content/README.md`` describes: the NPS API says
what the NPS publishes — names, descriptions, fees, hours, visitor centres, photographs —
and the curated files say what Unigrids wrote or chose. Nothing here invents a figure. A
value the sources do not carry is left out, and the app renders it as absent.
"""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

from ... import (
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
    coordinate,
    encode_outline,
    extent,
    guide_image,
    latest_raw,
    latest_raw_or_none,
    number,
    photo_filename,
    resize,
    wikimedia_image,
)

# Source key → place identifier, committed so an identifier outlives a renamed record
# (``ids.Registry``). National parks, NPS units and curated sites key on their own stable
# codes and do not need it.
PLACE_REGISTRY = config.CONTENT_DIR / "ids" / "places.json"

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


def assemble(context: BuildContext) -> Contribution:
    """Every US place, sight, outline, guide and layer. ``context.online`` lets the build
    fetch what it can only know once the places exist — Wikipedia articles for the ones
    without prose — into the raw store; offline, it reads what an earlier run cached."""
    raw = latest_raw("nps-api")
    print(f"    reading raw/{raw.name}")
    api = _NPSData(raw / "nps-api")
    outlines = unit_outlines(latest_raw("unit-boundaries") / "unit-boundaries")
    padus, padus_acres = _padus_outlines(rawstore.require("padus", "curated.geojson"))
    wikipedia = _wikipedia(latest_raw("wikipedia") / "wikipedia")
    photos_dir = latest_raw_or_none("photos")
    registry = ids.Registry(PLACE_REGISTRY)

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
            context.images_dir,
            outlines.get(code),
        )
        outline_entry = encode_outline(outlines.get(code), NATIONAL_PARK_TOLERANCE)
        if outline_entry:
            boundaries[place["id"]] = outline_entry
            place["extent"] = extent(outline_entry["bbox"])
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
        outline_entry = encode_outline(outlines.get(code), OTHER_TOLERANCE)
        if outline_entry:
            boundaries[place["id"]] = outline_entry
            place["extent"] = extent(outline_entry["bbox"])
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
    lands = latest_raw_or_none("federal-lands")
    if lands is not None:
        routes = lands_build.build(lands, places, boundaries, registry)
    transport_dir = latest_raw_or_none("transport")
    transport = lands_build.build_transport(transport_dir) if transport_dir else None
    trails_dir = latest_raw_or_none("trails-national")
    catalogue = trail_catalogue.build(trails_dir, outlines, pois) if trails_dir else None
    brochures_dir = latest_raw_or_none("brochures")
    documents = brochures.build(brochures_dir, places) if brochures_dir else None
    climate_dir = latest_raw_or_none("climate")
    normals = climate.build(climate_dir) if climate_dir else None

    pois.extend(_stamp_locations(places, pois, api))
    visitation.attach(places, visitation.build(rawstore.latest(visitation.SOURCE, visitation.FILE)))
    park_elevation.attach(places, rawstore.latest(park_elevation.SOURCE, park_elevation.FILE))
    assign_time_zones(places)
    regions = reference_content.passport_regions()
    for place in places:
        if region := regions.get(place["id"]):
            place["passportRegion"] = region

    if context.online:
        wikipedia_match.fetch(places, rawstore.today())
    wikipedia_match.enrich(
        places,
        boundaries,
        routes,
        rawstore.latest(wikipedia_match.SOURCE, wikipedia_match.PAGES_FILE),
        wikimedia_image,
    )

    # The other public lands carry no prose by design (lands_build); only an NPS unit or
    # a curated site without one is worth reporting.
    expects_summary = curated_ids | {
        place["id"] for place in places if place["kind"] in ("nationalPark", "npsUnit")
    }
    return Contribution(
        places=places,
        pois=pois,
        boundaries=boundaries,
        routes=routes,
        guides=guides,
        transport=transport,
        trails=catalogue,
        documents=documents,
        climate=normals,
        expects_summary=expects_summary,
        registries=[registry],
    )


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
            if (c := coordinate(r)) and outline.contains(polygons, c["longitude"], c["latitude"])
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
        # Named for the photograph, not its place in the gallery: a resized copy is kept
        # as long as its name exists, so a positional name kept last year's picture under
        # this year's caption and credit when the NPS reordered its photos.
        name = f"{place_id}-{Path(photo_filename(image['url'])).stem[:10]}.jpg"
        size, quality = (HERO_SIZE, HERO_QUALITY) if hero is None else (
            GALLERY_SIZE, GALLERY_QUALITY
        )
        # A photograph already resized is left alone: rewriting identical bytes on every
        # build churns a synced checkout, and iCloud answers churn with conflict copies.
        if (images_dir / name).exists():
            pass
        elif source is not None and source.exists():
            if not resize(source, images_dir / name, size, quality):
                continue
        elif not (images_dir / name).exists():
            continue
        entry = guide_image(image, asset_name=name)
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

    centre = coordinate(park) or {"latitude": row["centre"][0], "longitude": row["centre"][1]}
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
        "summary": summary or clean(park.get("description")),
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
        ("weather", clean(park.get("weatherInfo"))),
        ("directions", clean(park.get("directionsInfo"))),
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
        location = coordinate(match) if match else None
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
            or _without_notices(clean((match or {}).get("listingDescription"))),
            "hasStamp": False,
        }
        if match:
            photo = reference_content.choose_photos(match.get("images") or [], limit=1)
            if photo:
                poi["image"] = guide_image(photo[0])
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
        location = coordinate(centre)
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
            "summary": _first_sentences(_without_notices(clean(centre.get("description"))), 2),
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
        location = coordinate(camp)
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
            "summary": _first_sentences(_without_notices(clean(camp.get("description"))), 1),
            "hasStamp": False,
        })
    return result


def _camping_lines(camps: list[dict[str, Any]]) -> list[str]:
    lines = []
    for camp in sorted(camps, key=lambda c: c.get("name") or ""):
        name = (camp.get("name") or "").strip()
        if not name:
            continue
        reservable = int(number(camp.get("numberOfSitesReservable")) or 0)
        first_come = int(number(camp.get("numberOfSitesFirstComeFirstServe")) or 0)
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
        "name": lands_build.lower_small_words(
            clean(park.get("name")) or clean(park.get("fullName"))
        ),
        "designation": clean(park.get("designation")) or _designation_from_name(park),
        "kind": "npsUnit",
        "agency": "nps",
        "states": states,
        "centre": coordinate(park),
        "npsParkCode": code,
        "facts": facts,
        "officialURL": park.get("url"),
        "summary": clean(park.get("description")),
        "summarySource": "National Park Service",
    }
    if activities := _activities(park):
        place["activities"] = activities
    if photo:
        place["image"] = guide_image(photo[0])
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
        ("directions", clean(park.get("directionsInfo"))),
        ("weather", clean(park.get("weatherInfo"))),
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
    full = clean(park.get("fullName")) or ""
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
    outline_entry = encode_outline(polygons, OTHER_TOLERANCE)
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
        "extent": extent(outline_entry["bbox"]),
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
        image = wikimedia_image(wiki.get("_licence"))
        if image:
            place["image"] = image
    return place, outline_entry


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


def unit_outlines(directory: Path) -> dict[str, list[outline.Polygon]]:
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


# MARK: - NPS text and figures


def _fees(park: dict[str, Any]) -> list[dict[str, Any]]:
    fees = []
    for fee in park.get("entranceFees") or []:
        cost = number(fee.get("cost"))
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
        fees.append({"title": title, "cost": price, "detail": clean(fee.get("description"))})
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
        "detail": clean(fees_passes.get("entranceFeeDescription")),
    }]


def _timed_entry(fees_passes: dict[str, Any]) -> str | None:
    """The NPS's own timed-entry or reservation note, where it publishes one."""
    heading = clean(fees_passes.get("timedEntryHeading"))
    body = _without_notices(clean(fees_passes.get("timedEntryDescription")))
    if not body:
        return None
    return f"{heading}: {body}" if heading and not body.startswith(heading) else body


def _hours_note(park: dict[str, Any]) -> str | None:
    hours = park.get("operatingHours") or []
    return clean(hours[0].get("description")) if hours else None


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
    return _first_sentences(_without_notices(clean(hours[0].get("description"))), 1)


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


def _first_sentences(text: str | None, count: int) -> str | None:
    if not text:
        return None
    sentences = re.split(r"(?<=[.!?])\s+(?=[A-Z])", text)
    return " ".join(sentences[:count]).strip()


def _normal(text: str) -> str:
    return ids.slug(text).replace("-", " ").strip()
