"""Canada's share of the reference dataset.

The 48 national parks, reserves and Rouge with their guides; the five national marine
conservation areas; every provincial and territorial park of 100 km² or more; their
outlines; the guides' sights, and Parks Canada's visitor centres, campgrounds and huts in
and beside each national park, with OpenStreetMap's huts where Parks Canada lists none;
Parks Canada's trails; VIA Rail's lines and the stations near the parks; each park's
climate, attendance, and page with its brochures and maps.

The split of responsibility is New Zealand's: CPCAD says what an area is — its name,
outline, official area and province — Parks Canada's layers what is in it, and the curated
guides what Unigrids wrote or chose. Nothing here invents a figure. A value the sources do
not carry is left out, and the app renders it as absent.
"""

from __future__ import annotations

import json
import re
from typing import Any

from ... import climate, geo, ids, outline, rawstore
from ..abroad import elevation as abroad_elevation
from ..abroad import trails as abroad_trails
from ..base import BuildContext, Contribution
from ..common import (
    NATIONAL_PARK_TOLERANCE,
    OTHER_TOLERANCE,
    assign_time_zones,
    clean,
    encode_outline,
    extent,
    strip_tags,
)
from ..no import assembly as norway
from ..no import transport as rail
from . import content, rules, wiki
from .fetching import (
    ATTENDANCE,
    CLIMATE,
    COMMONS,
    CPCAD,
    DOCUMENTS,
    FACILITIES,
    HUTS_FILE,
    OSM,
    PHOTOS,
    RAIL_FILE,
    STATIONS_FILE,
    WIKIDATA,
    WIKIPEDIA,
    Area,
    marine_areas,
    national_parks,
    place_name,
    read_areas,
    read_attendance,
    read_candidates,
    read_layer,
    second_tier,
    wiki_matches,
)

COUNTRY = "CA"
PARKS_CANADA = "parksCanada"
PROVINCIAL_AGENCY = "provincialAgency"

POI_KINDS = frozenset({"sight", "viewpoint", "visitorCentre", "entrance", "trailhead"})
RANKED_KINDS = frozenset({"sight", "viewpoint"})

# How far outside a park a Parks Canada visitor centre may stand and still be that park's
# (the centres in Jasper, Banff and Waterton townsites are inside; Churchill's, Inuvik's and
# Pangnirtung's are in the town the park is reached from, and name the park).
VISITOR_CENTRE_REACH_KM = 10.0
# A campground or hut on a park's boundary line, as Parks Canada's points sometimes sit.
EDGE_REACH_KM = 1.0
# A guide's visitor centre this close to Parks Canada's is the same building; two huts
# this close, Parks Canada's and OpenStreetMap's, are one.
SAME_PLACE_M = 500.0
# How far a campsite of the accommodation layer may lie from the campground point whose
# name it carries.
CAMPSITE_REACH_M = 3000.0

DEFAULT_CREDITS = [
    "Text written for Unigrids. Facts checked against Parks Canada's pages and the sources "
    "below.",
    "Park outline: Canadian Protected and Conserved Areas Database, Environment and Climate "
    "Change Canada, Open Government Licence – Canada. The outline is simplified by Unigrids.",
]

# Words in a Commons file's author or credit that say it is Parks Canada's own
# photograph, which Unigrids does not use.
_PARKS_CANADA_PHOTO = re.compile(r"\bparks canada\b|\bparcs canada\b", re.IGNORECASE)


def assemble(context: BuildContext) -> Contribution:
    """Every Canadian place, point of interest, outline, guide and layer, from the raw
    store and ``content/countries/ca/``. Offline by design: ``context.online`` only lets
    trails and elevation tiles that were not fetched be fetched now."""
    cpcad_dir = rawstore.latest(CPCAD, "national-parks.geojson")
    if cpcad_dir is None:
        raise SystemExit(f"no raw/{CPCAD} yet: run Canada's fetch with network")
    print(f"    reading raw/{cpcad_dir.parent.name}/{CPCAD}")
    areas = read_areas(cpcad_dir)
    sources = _Sources()
    report = norway._Report()
    sources.refuse_parks_canada_photos(report)

    place_registry = ids.country_registry("ca", "places")
    poi_registry = ids.country_registry("ca", "pois")

    places: list[dict[str, Any]] = []
    pois: list[dict[str, Any]] = []
    boundaries: dict[str, Any] = {}
    guides: dict[str, Any] = {}
    parks: list[dict[str, Any]] = []
    park_outlines: dict[str, Any] = {}
    park_areas: dict[str, Area] = {}

    for park, area in national_parks(areas):
        if area is None or not area.polygons:
            report.add("parks without an outline", park["id"])
            continue
        outline_entry = encode_outline(area.polygons, NATIONAL_PARK_TOLERANCE)
        if not outline_entry:
            report.add("parks without an outline", park["id"])
            continue
        parks.append(park)
        park_outlines[park["id"]] = area.polygons
        park_areas[park["id"]] = area
        place, guide, park_pois = _national_park(park, area, sources, poi_registry, context,
                                                 report)
        boundaries[place["id"]] = outline_entry
        place["extent"] = extent(outline_entry["bbox"])
        places.append(place)
        pois.extend(park_pois)
        guides[place["id"]] = guide
    facility_pois, trailheads = _facilities(park_areas, pois, sources, poi_registry, report)
    pois.extend(facility_pois)
    pois.extend(_osm_huts(park_areas, pois, sources, poi_registry))

    sources.matches = wiki_matches(areas, sources.candidates)
    for area in [*marine_areas(areas), *second_tier(areas)]:
        tolerance = OTHER_TOLERANCE
        outline_entry = encode_outline(area.polygons, tolerance)
        if not outline_entry:
            report.add("left out: no outline at the map's scale", area.parent_id)
            continue
        place = _second_tier_place(area, sources, place_registry, report)
        if place is None:
            continue
        boundaries[place["id"]] = outline_entry
        place["extent"] = extent(outline_entry["bbox"])
        places.append(place)

    # Trails from Parks Canada's layer (OpenStreetMap where it has none), measured as the
    # US's are, walked from the trailheads, campgrounds and visitor centres; and each
    # park's lowest and highest ground, from Copernicus GLO-30.
    trail_registry = ids.country_registry("ca", "trails")
    pois_by_park: dict[str, list[dict[str, Any]]] = {}
    for poi in [*pois, *trailheads]:
        pois_by_park.setdefault(poi["placeID"], []).append(poi)
    trails = abroad_trails.build(
        "ca", parks, park_outlines, pois_by_park, online=context.online, registry=trail_registry
    )
    abroad_elevation.attach_extremes(places, park_outlines, online=context.online)

    _zone(places, report)
    lines = _transport(park_areas)
    normals = climate.build(sources.climate) if sources.climate else None
    documents = _documents(places, sources)
    _report_counts(areas)

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
        transport=lines,
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
        self.candidates = read_candidates(rawstore.latest(WIKIDATA, "candidates.json"))
        self.matches: dict[str, dict[str, Any]] = {}
        self.summaries = norway._json(rawstore.latest(WIKIPEDIA, "summaries.json"),
                                      "summaries.json")
        self.licences = norway._json(rawstore.latest(COMMONS, "licences.json"), "licences.json")
        self.photos = rawstore.latest(PHOTOS)
        self.documents = norway._json(rawstore.latest(DOCUMENTS, "links.json"), "links.json")
        facilities = rawstore.latest(FACILITIES)
        self.facilities = [
            feature for feature in read_layer(facilities, "facilities.geojson")
            if _point(feature) is not None
        ]
        self.accommodation = [
            feature for feature in read_layer(facilities, "accommodation.geojson")
            if _point(feature) is not None
        ]
        if facilities is None:
            print(f"    no raw/{FACILITIES}: no visitor centres, campgrounds or huts this run")
        self.attendance = read_attendance(rawstore.latest(ATTENDANCE, "attendance.csv"))
        osm_dir = rawstore.latest(OSM, HUTS_FILE)
        self.huts = (
            rail.huts(json.loads((osm_dir / HUTS_FILE).read_text())) if osm_dir else []
        )
        self.climate = rawstore.latest(CLIMATE)

    def refuse_parks_canada_photos(self, report: norway._Report) -> None:
        """Leave out any Commons file that is Parks Canada's own photograph: one whose
        author or credit names Parks Canada. A description that only mentions the agency
        (a photograph of its sign, a link to its page) does not make it Parks Canada's."""
        for name, licence in list(self.licences.items()):
            text = " ".join(
                strip_tags(str((licence or {}).get(key) or ""))
                for key in ("artist", "credit", "uploader")
            )
            if licence and _PARKS_CANADA_PHOTO.search(text):
                self.licences[name] = None
                report.add("photographs refused as Parks Canada's own", name)


def _point(feature: dict[str, Any]) -> tuple[float, float] | None:
    """``(latitude, longitude)`` of a point feature."""
    geometry = feature.get("geometry") or {}
    coordinates = geometry.get("coordinates") if geometry.get("type") == "Point" else None
    if not coordinates or len(coordinates) < 2:
        return None
    longitude, latitude = float(coordinates[0]), float(coordinates[1])
    if not (-90 <= latitude <= 90 and -180 <= longitude <= 180):
        return None
    return latitude, longitude


# MARK: - Where a place is


def _zone(places: list[dict[str, Any]], report: norway._Report) -> None:
    """Each place's zone at its centre, held to Canada's zones; a centre at sea takes its
    province's main zone."""
    assign_time_zones(places)
    for place in places:
        codes = [code.removeprefix("CA-") for code in place.get("subdivisions") or []]
        expected = rules.time_zone(place.get("timeZoneID"), codes)
        if expected is None:
            report.add("places with no zone", place["id"])
            place.pop("timeZoneID", None)
            continue
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
    report: norway._Report,
) -> tuple[dict[str, Any], dict[str, Any], list[dict[str, Any]]]:
    place_id = park["id"]
    guide = content.guide(place_id)
    if guide is None:
        report.add("parks without a guide", place_id)
        guide = {}
    subdivisions = area.subdivisions()
    if not subdivisions:
        report.add("parks in no province", place_id)

    hero, gallery = norway._park_photos(place_id, guide, sources, context.images_dir, report)
    if hero is None:
        report.add("parks without a photograph", place_id)
    official = park.get("pcPage")

    facts = norway._facts(place_id, guide, report)
    if (place := park.get("attendancePlace")) and (visits := sources.attendance.get(place)):
        facts["annualVisits"] = visits
        facts["annualVisitsYear"] = rules.ATTENDANCE_FISCAL_YEAR[0]
        facts["annualVisitsPeriod"] = rules.attendance_period()
    elif place:
        report.add("attendance rows not found or not counted", f"{place_id}: {place}")

    record_place: dict[str, Any] = {
        "id": place_id,
        "name": park["name"],
        "designation": park["designation"],
        "kind": "nationalPark",
        "agency": PARKS_CANADA,
        "country": COUNTRY,
        "subdivisions": subdivisions,
        "centre": _centre(area),
        "themes": norway._themes(place_id, guide, report),
        "facts": facts,
        "passportRegion": park["passportRegion"],
    }
    if park["passportRegion"] not in rules.PASSPORT_REGIONS:
        report.add("parks with an unknown passport region", place_id)
    if official:
        record_place["officialURL"] = official
    if summary := clean(guide.get("summary")):
        record_place["summary"] = summary
        record_place["summarySource"] = "Unigrids"
    if hero:
        record_place["image"] = hero
    names = [
        {"language": entry["language"], "text": entry["text"]}
        for entry in park.get("localNames") or []
        if isinstance(entry, dict) and entry.get("language") and entry.get("text")
    ]
    if names:
        record_place["localNames"] = names
    if reached_by := clean(park.get("reachedBy")):
        record_place["reachedBy"] = reached_by

    pois = _guide_pois(place_id, guide, poi_registry, report)

    sources_list = []
    for source in guide.get("sources") or []:
        if not isinstance(source, dict) or not (source.get("title") or source.get("url")):
            continue
        entry = {"title": clean(source.get("title")) or source["url"]}
        if source.get("url"):
            entry["url"] = source["url"]
        sources_list.append(entry)
    if official and not any("parks.canada.ca" in (s.get("url") or "") for s in sources_list):
        sources_list.append({"title": f"{park['officialName']} — Parks Canada", "url": official})

    record: dict[str, Any] = {
        "placeID": place_id,
        "contentVersion": guide.get("contentVersion", 1),
        "story": norway._strings(guide.get("story")),
        "howItWorks": norway._strings(guide.get("howItWorks")),
        "sightNotes": {
            poi["id"]: poi["summary"]
            for poi in pois
            if poi["kind"] in RANKED_KINDS and poi.get("summary")
        },
        "planYourVisit": norway._plan(guide.get("planYourVisit")),
        "chronology": [
            {"year": str(entry["year"]), "text": entry["text"]}
            for entry in guide.get("chronology") or []
            if isinstance(entry, dict) and entry.get("year") and entry.get("text")
        ],
        "safety": norway._strings(guide.get("safety")),
        "regulations": norway._strings(guide.get("regulations")),
        "credits": _credits(guide),
        "sources": sources_list,
        "fees": norway._fees(guide.get("fees")),
    }
    if hero:
        record["hero"] = hero
    if gallery:
        record["gallery"] = gallery
    for key in ("operatingHours", "weather", "directions"):
        if text := clean(guide.get(key)):
            record[key] = text
    return record_place, record, pois


def _credits(guide: dict[str, Any]) -> list[str]:
    """The guide's own credits, or the default; either way ending with the outline's
    credit, which says it was changed (simplified) by Unigrids."""
    credits = norway._strings(guide.get("credits")) or DEFAULT_CREDITS[:1]
    if not any("Protected and Conserved Areas" in line for line in credits):
        credits.append(DEFAULT_CREDITS[1])
    return credits


# MARK: - Points of interest


def _guide_pois(
    place_id: str, guide: dict[str, Any], registry: ids.Registry, report: norway._Report
) -> list[dict[str, Any]]:
    """The guide's sights, ranked in the guide's order, and its visitor centres."""
    slug = content.park_slug(place_id)
    pois: list[dict[str, Any]] = []
    seen: set[str] = set()
    rank = 0
    for sight in guide.get("sights") or []:
        name = clean((sight or {}).get("name"))
        location = location_of((sight or {}).get("location"))
        kind = (sight or {}).get("kind") or "sight"
        if not name or location is None or kind not in POI_KINDS:
            report.add("guide sights left out", f"{place_id}: {name or sight!r}")
            continue
        try:
            poi_id = ids.country_poi_id(registry, "ca", slug, f"guide:{place_id}:{name}", name)
        except ids.UnromanisedNameError:
            # A name in a script the slug cannot carry (syllabics): keyed by its Latin
            # letters, which stay the same as long as the name does.
            latin = ids.slug(name) or "sight"
            poi_id = ids.country_poi_id(registry, "ca", slug, f"guide:{place_id}:{latin}", latin)
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


def location_of(value: Any) -> dict[str, float] | None:
    """A guide's ``[latitude, longitude]``, if it lies in Canada's box."""
    if not isinstance(value, list | tuple) or len(value) != 2:
        return None
    latitude, longitude = value
    if not isinstance(latitude, int | float) or not isinstance(longitude, int | float):
        return None
    if not (41.6 <= latitude <= 83.2 and -141.1 <= longitude <= -52.5):
        return None
    return {"latitude": round(float(latitude), 5), "longitude": round(float(longitude), 5)}


def _location(point: tuple[float, float]) -> dict[str, float]:
    return {"latitude": round(point[0], 5), "longitude": round(point[1], 5)}


def _nearest_park(
    point: tuple[float, float], park_areas: dict[str, Area], reach_km: float
) -> tuple[float, str] | None:
    """The park the point lies in, or the nearest within ``reach_km`` of one."""
    nearest: tuple[float, str] | None = None
    for park_id, area in park_areas.items():
        box = area.box
        if box is None or not _within(box.buffered(reach_km * 1000), point):
            continue
        if outline.contains(area.polygons, point[1], point[0]):
            return 0.0, park_id
        distance = rail.distance_to_outline_km(point, _coarse(area))
        if distance <= reach_km and (nearest is None or distance < nearest[0]):
            nearest = (distance, park_id)
    return nearest


def _facilities(
    park_areas: dict[str, Area],
    pois: list[dict[str, Any]],
    sources: _Sources,
    registry: ids.Registry,
    report: norway._Report,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    """Parks Canada's visitor centres, campgrounds and huts given to the park they stand in
    or beside, and its trailheads, which only anchor the trails' walking order. A visitor
    centre a guide already lists is left to the guide."""
    found: list[dict[str, Any]] = []
    trailheads: list[dict[str, Any]] = []
    names = {park["id"]: park for park in content.parks()}
    keys: dict[str, int] = {}
    for feature in sources.facilities:
        properties = feature.get("properties") or {}
        point = _point(feature)
        assert point is not None
        name = rules.facility_name(properties)
        kind = rules.facility_kind(properties)
        if properties.get("Facility_Type_Installation") == rules.TRAILHEAD:
            nearest = _nearest_park(point, park_areas, EDGE_REACH_KM)
            if nearest is not None:
                trailheads.append({"placeID": nearest[1], "kind": "trailhead",
                                   "location": _location(point)})
            continue
        if kind is None or not name:
            continue
        reach = VISITOR_CENTRE_REACH_KM if kind == "visitorCentre" else EDGE_REACH_KM
        nearest = _nearest_park(point, park_areas, reach)
        if kind == "visitorCentre":
            # A centre that names its park is that park's, however far the town is.
            for park_id, park in names.items():
                if park_id in park_areas and park["name"].lower() in name.lower():
                    nearest = (0.0, park_id)
        if nearest is None:
            if kind == "visitorCentre":
                report.add("Parks Canada visitor centres near no national park", name)
            continue
        park_id = nearest[1]
        if kind == "visitorCentre" and any(
            poi["placeID"] == park_id and poi["kind"] == "visitorCentre"
            and rail.metres(point, (poi["location"]["latitude"], poi["location"]["longitude"]))
            <= SAME_PLACE_M
            for poi in pois
        ):
            continue
        if any(
            poi["placeID"] == park_id and poi["kind"] == kind and poi["name"] == name
            and rail.metres(point, (poi["location"]["latitude"], poi["location"]["longitude"]))
            <= 100
            for poi in found
        ):
            continue  # the same facility recorded twice
        slug = content.park_slug(park_id)
        base = f"parkscanada:facility/{slug}/{kind}/{ids.slug(name)}"
        keys[base] = keys.get(base, 0) + 1
        key = base if keys[base] == 1 else f"{base}@{point[0]:.3f},{point[1]:.3f}"
        sites = None
        if kind == "campground":
            sites = rules.accommodation_counts(_campsites(properties, point, sources))
        poi: dict[str, Any] = {
            "id": ids.country_poi_id(registry, "ca", slug, key, name),
            "placeID": park_id,
            "kind": kind,
            "name": name,
            "location": _location(point),
            "rank": 0,
            "hasStamp": False,
            "summary": rules.facility_summary(properties, sites),
        }
        if url := rules.official_url(properties.get("URL_e")):
            poi["url"] = url
        found.append(poi)
    # Backcountry huts and shelters the accommodation layer lists and the facilities do
    # not (the Alpine Club's huts in Yoho and Glacier).
    for feature in sources.accommodation:
        properties = feature.get("properties") or {}
        if properties.get("Accommodation_Type") != rules.BACKCOUNTRY_ACCOMMODATION:
            continue
        point = _point(feature)
        assert point is not None
        name = rules.facility_name(properties)
        nearest = _nearest_park(point, park_areas, EDGE_REACH_KM)
        if not name or nearest is None or re.match(r"(?i)cabins?\b", name):
            continue
        park_id = nearest[1]
        if _near_hut(found, park_id, point, name):
            continue
        slug = content.park_slug(park_id)
        key = f"parkscanada:accommodation/{slug}/{ids.slug(name)}"
        found.append({
            "id": ids.country_poi_id(registry, "ca", slug, key, name),
            "placeID": park_id,
            "kind": "hut",
            "name": re.sub(r"^ACC hut - ", "", name) + (" Hut" if name.startswith("ACC hut")
                                                       and "hut" not in name[9:].lower() else ""),
            "location": _location(point),
            "rank": 0,
            "hasStamp": False,
            "summary": "Backcountry hut" + (
                " · Alpine Club of Canada" if name.startswith("ACC") else ""
            ),
        })
    return sorted(found, key=lambda poi: (poi["placeID"], poi["kind"], poi["name"],
                                          poi["id"])), trailheads


def _campsites(
    properties: dict[str, Any], point: tuple[float, float], sources: _Sources
) -> list[dict[str, Any]]:
    """The accommodation layer's sites that carry a campground's name and lie near it."""
    wanted = {rules.normal(properties.get("Name_e")), rules.normal(properties.get("Label_e"))}
    wanted.discard("")
    found = []
    for feature in sources.accommodation:
        site = feature.get("properties") or {}
        if rules.normal(site.get("Name_e")) not in wanted:
            continue
        here = _point(feature)
        assert here is not None
        if rail.metres(point, here) <= CAMPSITE_REACH_M:
            found.append(site)
    return found


def _near_hut(
    pois: list[dict[str, Any]], park_id: str, point: tuple[float, float], name: str
) -> bool:
    """Whether a hut is one already listed: within :data:`SAME_PLACE_M`, or of the same
    name in the same park."""
    wanted = rules.normal(name)
    for poi in pois:
        if poi["placeID"] != park_id or poi["kind"] not in ("hut", "campground"):
            continue
        here = (poi["location"]["latitude"], poi["location"]["longitude"])
        if rail.metres(point, here) <= SAME_PLACE_M or (
            poi["kind"] == "hut" and wanted and rules.normal(poi["name"]) == wanted
        ):
            return True
    return False


def _osm_huts(
    park_areas: dict[str, Area],
    pois: list[dict[str, Any]],
    sources: _Sources,
    registry: ids.Registry,
) -> list[dict[str, Any]]:
    """The named huts OpenStreetMap maps inside a park's own outline that Parks Canada's
    layers do not list."""
    found: list[dict[str, Any]] = []
    for element in sources.huts:
        point = rail.point_of(element)
        assert point is not None
        nearest = _nearest_park(point, park_areas, 0.0)
        if nearest is None:
            continue
        park_id = nearest[1]
        tags = element.get("tags") or {}
        name = re.sub(r"\s+", " ", tags["name"]).strip()
        # A warden's patrol cabin, a private hut or a closed one is not a place to stay.
        if tags.get("access") in ("private", "no") or _NOT_PUBLIC_HUT.search(name):
            continue
        if _near_hut([*pois, *found], park_id, point, name):
            continue
        slug = content.park_slug(park_id)
        poi: dict[str, Any] = {
            "id": ids.country_poi_id(registry, "ca", slug, rail.key_of(element), name),
            "placeID": park_id,
            "kind": "hut",
            "name": name,
            "location": _location(point),
            "rank": 0,
            "hasStamp": False,
        }
        if summary := osm_hut_summary(tags):
            poi["summary"] = summary
        website = tags.get("website") or tags.get("contact:website") or ""
        if website.startswith(("http://", "https://")):
            poi["url"] = website
        found.append(poi)
    return sorted(found, key=lambda poi: (poi["placeID"], poi["name"]))


_NOT_PUBLIC_HUT = re.compile(r"\bwardens?'?s?\b|\(closed\)|\bpatrol\b", re.IGNORECASE)


def osm_hut_summary(tags: dict[str, str]) -> str | None:
    """"Alpine hut · Alpine Club of Canada", from the hut's own tags."""
    parts = []
    kind = {"alpine_hut": "Alpine hut", "wilderness_hut": "Wilderness hut"}.get(
        tags.get("tourism") or ""
    )
    if kind:
        parts.append(kind)
    operator = (tags.get("operator") or "").strip()
    if operator and not operator.startswith(("http://", "https://", "www.")):
        parts.append(operator)
    return " · ".join(parts) or None


def _within(box: geo.BoundingBox, point: tuple[float, float]) -> bool:
    latitude, longitude = point
    return box.south <= latitude <= box.north and box.west <= longitude <= box.east


_COARSE: dict[str, list[Any]] = {}


def _coarse(area: Area) -> list[Any]:
    """The park's outline generalised to about 500 m, for distances in kilometres."""
    key = f"{area.tier}:{area.key}"
    if key not in _COARSE:
        _COARSE[key] = outline.generalise(area.polygons, 0.005) or area.polygons
    return _COARSE[key]


# MARK: - Second tier


def _second_tier_place(
    area: Area, sources: _Sources, registry: ids.Registry, report: norway._Report
) -> dict[str, Any] | None:
    """A marine conservation area or a provincial or territorial park: named, outlined,
    located and measured from CPCAD, and described by its Wikipedia lead where it has one."""
    subdivisions = area.subdivisions()
    region = rules.passport_region(subdivisions[0].removeprefix("CA-")) if subdivisions else None
    if not subdivisions or not region:
        report.add("left out: in no province", f"{area.parent_id} {area.name}")
        return None
    name, designation = place_name(area)
    marine = area.tier == "mca"
    proposed = None
    for candidate in rules.identifier_names(name, designation):
        try:
            proposed = ids.country_place_id("ca", area.tier, candidate)
            break
        except ids.UnromanisedNameError:
            continue
    if proposed is None:
        report.add("left out: no Latin name to make an identifier from", area.parent_id)
        return None
    province = next(
        (title for code, title in rules.LOCATIONS.values() if f"CA-{code}" == subdivisions[0]),
        "",
    )
    place_id = registry.resolve(
        f"cpcad:{area.parent_id}", proposed,
        qualifier=ids.romanised_slug(province) if province else None,
    )
    facts: dict[str, Any] = {}
    if (hectares := area.official_hectares) is not None:
        facts["areaHectares"] = round(hectares)
    if marine and (row := rules.MARINE_ATTENDANCE.get(area.key)) and (
        visits := sources.attendance.get(row)
    ):
        facts["annualVisits"] = visits
        facts["annualVisitsYear"] = rules.ATTENDANCE_FISCAL_YEAR[0]
        facts["annualVisitsPeriod"] = rules.attendance_period()
    place: dict[str, Any] = {
        "id": place_id,
        "name": name,
        "designation": designation,
        "kind": "marineConservationArea" if marine else "provincialPark",
        "agency": PARKS_CANADA if marine else PROVINCIAL_AGENCY,
        "country": COUNTRY,
        "subdivisions": subdivisions,
        "centre": _centre(area),
        "facts": facts,
        "passportRegion": region,
    }
    french = clean(area.main.get("NAME_F"))
    if area.main.get("TYPE_E") == "Quebec's national park" and french:
        place["localNames"] = [{"language": "fr", "text": french}]
    key = f"{area.tier}:{area.key}"
    item = sources.matches.get(key)
    summary = sources.summaries.get(key) if item else None
    if summary and summary.get("type") != "disambiguation" and summary.get("extract"):
        page = ((summary.get("content_urls") or {}).get("desktop") or {}).get("page")
        place["summary"] = wiki.lead(summary["extract"])
        place["summarySource"] = "Wikipedia"
        place["summaryLicence"] = wiki.LICENCE
        if page:
            place["summaryURL"] = page
            place["infoURL"] = page
    if item and (image := norway._linked_image(wiki.file_name(item.get("image")), sources)):
        place["image"] = image
    return place


def _report_counts(areas: dict[str, Area]) -> None:
    tiers: dict[str, int] = {}
    for area in areas.values():
        tiers[area.tier] = tiers.get(area.tier, 0) + 1
    print(f"    CPCAD: {tiers.get('np', 0)} national parks, {tiers.get('mca', 0)} marine areas, "
          f"{tiers.get('pp', 0)} provincial and territorial parks fetched")


# MARK: - Transport


def is_via(tags: dict[str, str]) -> bool:
    """A VIA Rail route, by its operator, network or brand."""
    text = " ".join(tags.get(key) or "" for key in ("operator", "network", "brand"))
    return bool(re.search(r"\bVIA\b", text))


def pair_directions(routes: list[rail.Route]) -> None:
    """VIA numbers each direction of a service as a train of its own (1 west, 2 east):
    the two directions between the same ends are drawn as one line, under the lower
    number."""
    pairs: dict[frozenset[str], list[rail.Route]] = {}
    for route in routes:
        ends = (route.tags.get("from") or "").strip(), (route.tags.get("to") or "").strip()
        if all(ends) and route.ref:
            pairs.setdefault(frozenset(ends), []).append(route)
    for group in pairs.values():
        lowest = min((route.ref for route in group),
                     key=lambda ref: (int(ref) if ref.isdigit() else 10**9, ref))
        for route in group:
            route.tags = {**route.tags, "ref": lowest}


def _transport(park_areas: dict[str, Area]) -> dict[str, list[Any]] | None:
    """``railLines`` (VIA Rail's) and ``railStations`` within reach of a park that a VIA
    line calls at, or nothing if the rail was never read."""
    directory = rawstore.latest(OSM, RAIL_FILE)
    if directory is None:
        print(f"    no raw/{OSM} rail routes: no rail layers this run")
        return None
    routes = {key: route for key, route in rail.read_routes(directory).items()
              if is_via(route.tags)}
    pair_directions(list(routes.values()))
    lines, belongs = rail.build_lines(routes, lambda latitude, longitude: True)
    payloads = []
    if (directory / STATIONS_FILE).exists():
        payloads.append(json.loads((directory / STATIONS_FILE).read_text()))
    stop_areas = rail.stop_areas(payloads)
    reach = [
        (area, box.buffered(rail.STATION_REACH_KM * 1000))
        for area in park_areas.values()
        if (box := area.box) is not None
    ]
    stations = []
    without_lines = 0
    for station in rail.stations(payloads):
        point = rail.point_of(station)
        assert point is not None
        near = any(
            _within(box, point)
            and rail.distance_to_outline_km(point, _coarse(area)) <= rail.STATION_REACH_KM
            for area, box in reach
        )
        if not near:
            continue
        names = rail.station_lines(station, routes, belongs, stop_areas)
        if not names:
            without_lines += 1
            continue
        entry = rail.station_entry(station, names)
        entry["country"] = COUNTRY
        stations.append(entry)
    print(
        f"    rail: {len(lines)} VIA Rail lines from {len(belongs)} routes; "
        f"{len(stations)} stations within {rail.STATION_REACH_KM:.0f} km of a park "
        f"({without_lines} with no VIA line left out)"
    )
    return {"railLines": lines, "railStations": stations}


# MARK: - Documents


def _documents(places: list[dict[str, Any]], sources: _Sources) -> dict[str, Any] | None:
    """Each national park's page on parks.canada.ca and the PDFs its pages link that
    answered."""
    if not sources.documents:
        return None
    result: dict[str, Any] = {}
    rank = {"brochure": 0, "map": 1, "other": 2}
    for place in places:
        entry = sources.documents.get(place["id"])
        if place["kind"] != "nationalPark" or not entry:
            continue
        documents = [
            {**document, "kind": rules.document_kind(document["title"], document["url"])}
            for document in entry.get("documents") or []
        ]
        documents.sort(key=lambda doc: rank[doc["kind"]])
        result[place["id"]] = {"page": entry.get("page"), "documents": documents}
    with_pdf = sum(1 for entry in result.values() if entry["documents"])
    print(f"    documents: {len(result)} park pages, {with_pdf} with a PDF")
    return result
