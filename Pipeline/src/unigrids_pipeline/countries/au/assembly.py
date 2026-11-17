"""Australia's share of the reference dataset.

The 51 national parks with a guide; every other park CAPAD types "National Park" (the
states' and territories' national parks, about 670); their outlines; the guides' sights,
and OpenStreetMap's visitor centres, campgrounds and huts in and beside each guided park;
the trails, from Queensland's own walking tracks in Queensland and OpenStreetMap; the
passenger lines and the stations near the parks; each guided park's climate and agency
page with its brochures and maps.

The split of responsibility is New Zealand's and Canada's: CAPAD says what an area is —
its name, outline, gazettal and area — the ABS's boundaries which state it lies in, and
the curated guides what Unigrids wrote or chose. Nothing here invents a figure. A value
the sources do not carry is left out, and the app renders it as absent. No agency
publishes visitor numbers per park, so none are carried.
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
)
from ..no import assembly as norway
from ..no import transport as rail
from . import content, rules, wiki
from .fetching import (
    CAPAD,
    CLIMATE,
    COMMONS,
    DOCUMENTS,
    FACILITIES_FILE,
    OSM,
    PHOTOS,
    RAIL_FILE,
    STATES,
    STATIONS_FILE,
    WIKIDATA,
    WIKIPEDIA,
    Area,
    national_parks,
    read_areas,
    read_candidates,
    second_tier,
    states_index,
    wiki_matches,
)

COUNTRY = "AU"
NATIONAL_PARK_KIND = "nationalPark"
STATE_NATIONAL_PARK_KIND = "stateNationalPark"

POI_KINDS = frozenset({"sight", "viewpoint", "visitorCentre", "entrance", "trailhead"})
RANKED_KINDS = frozenset({"sight", "viewpoint"})

# How far outside a park an OpenStreetMap visitor centre may stand and still be that
# park's, unless its name names the park: a town's own tourist office a few kilometres off
# (Katoomba's, Dunkeld's) is the town's. The guides list the centres in the gateway towns.
VISITOR_CENTRE_REACH_KM = 2.0
# How far a visitor centre that names its park may stand from it (Khancoban's Kosciuszko
# National Park office).
NAMED_CENTRE_REACH_KM = 50.0
# A campground or hut on a park's boundary line, as mapped points sometimes sit.
EDGE_REACH_KM = 1.0
# A guide's visitor centre this close to OpenStreetMap's is the same building.
SAME_PLACE_M = 500.0

DEFAULT_CREDITS = [
    "Text written for Unigrids. Facts checked against the park agency's pages and the "
    "sources below.",
    "Park outline: Collaborative Australian Protected Areas Database (CAPAD) 2024, © "
    "Commonwealth of Australia (DCCEEW), CC BY 4.0. The outline is simplified by Unigrids.",
]


def assemble(context: BuildContext) -> Contribution:
    """Every Australian place, point of interest, outline, guide and layer, from the raw
    store and ``content/countries/au/``. Offline by design: ``context.online`` only lets
    trails and elevation tiles that were not fetched be fetched now."""
    capad_dir = rawstore.latest(CAPAD, "national-parks.geojson")
    if capad_dir is None:
        raise SystemExit(f"no raw/{CAPAD} yet: run Australia's fetch with network")
    print(f"    reading raw/{capad_dir.parent.name}/{CAPAD}")
    areas = read_areas(capad_dir)
    sources = _Sources()
    report = norway._Report()

    place_registry = ids.country_registry("au", "places")
    poi_registry = ids.country_registry("au", "pois")

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
    pois.extend(_facilities(park_areas, pois, sources, poi_registry, report))

    sources.matches = wiki_matches(areas, sources.candidates)
    areas_found: dict[str, int] = {}
    for area in second_tier(areas):
        outline_entry = encode_outline(area.polygons, OTHER_TOLERANCE)
        if not outline_entry:
            report.add("left out: no outline at the map's scale", area.key)
            continue
        place = _second_tier_place(area, sources, place_registry, report, areas_found)
        if place is None:
            continue
        boundaries[place["id"]] = outline_entry
        place["extent"] = extent(outline_entry["bbox"])
        places.append(place)
    print(f"    state national parks' areas: {areas_found}")

    # Trails from Queensland's own layer and OpenStreetMap, measured as the US's are,
    # walked from the trailheads, campgrounds and visitor centres; and each park's lowest
    # and highest ground, from Copernicus GLO-30.
    trail_registry = ids.country_registry("au", "trails")
    pois_by_park: dict[str, list[dict[str, Any]]] = {}
    for poi in pois:
        pois_by_park.setdefault(poi["placeID"], []).append(poi)
    trails = abroad_trails.build(
        "au", parks, park_outlines, pois_by_park, online=context.online, registry=trail_registry
    )
    abroad_elevation.attach_extremes(places, park_outlines, online=context.online)

    _zone(places, report)
    lines = _transport(park_areas)
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
        transport=lines,
        documents=documents,
        climate=normals,
        expects_summary={place["id"] for place in places if place["kind"] == NATIONAL_PARK_KIND},
        trails=trails,
        registries=[place_registry, poi_registry, trail_registry],
    )


# MARK: - Raw sources


class _Sources:
    """The newest fetched copy of each source the build reads, or nothing."""

    def __init__(self) -> None:
        self.states = states_index(rawstore.latest(STATES, "states.geojson"))
        if self.states is None:
            print(f"    no raw/{STATES}: places are located by CAPAD's state alone")
        self.candidates = read_candidates(rawstore.latest(WIKIDATA, "candidates.json"))
        self.matches: dict[str, dict[str, Any]] = {}
        self.summaries = norway._json(rawstore.latest(WIKIPEDIA, "summaries.json"),
                                      "summaries.json")
        self.licences = norway._json(rawstore.latest(COMMONS, "licences.json"), "licences.json")
        self.photos = rawstore.latest(PHOTOS)
        self.documents = norway._json(rawstore.latest(DOCUMENTS, "links.json"), "links.json")
        osm_dir = rawstore.latest(OSM, FACILITIES_FILE)
        self.facilities = (
            [
                element
                for element in json.loads((osm_dir / FACILITIES_FILE).read_text()).get(
                    "elements"
                ) or []
                if rail.point_of(element) is not None
            ]
            if osm_dir else []
        )
        if osm_dir is None:
            print(f"    no raw/{OSM} facilities: no visitor centres, campgrounds or huts "
                  "beyond the guides' this run")
        self.climate = rawstore.latest(CLIMATE)


# MARK: - Where a place is


def locate(area: Area, sources: _Sources) -> str | None:
    """The state or territory a park lies in, as the app's code: the ABS's boundaries at
    the park's centre, else CAPAD's own ``STATE`` (an island the generalised boundaries
    miss)."""
    centre = area.centre
    found = None
    if sources.states is not None and centre is not None:
        found = sources.states.at(centre[0], centre[1])
    if found is None and centre is not None:
        found = rules.capad_state(area.state, centre[0], centre[1])
    return found


def _zone(places: list[dict[str, Any]], report: norway._Report) -> None:
    """Each place's zone at its centre, held to Australia's zones; a centre the lookup
    does not answer as Australian takes its state's main zone."""
    assign_time_zones(places)
    for place in places:
        codes = [code.removeprefix("AU-") for code in place.get("subdivisions") or []]
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


def split_name(name: str) -> tuple[str, str]:
    """``(name, designation)`` from the name an agency writes: "Kakadu National Park" →
    ("Kakadu", "National Park"); "Daintree National Park (CYPAL)" → ("Daintree",
    "National Park (CYPAL)"); "Grampians (Gariwerd) National Park" → ("Grampians
    (Gariwerd)", "National Park")."""
    match = re.match(r"^(?P<name>.+?)\s+National Park(?P<rest>\s*\(.+\))?\s*$", name.strip())
    if not match:
        return name.strip(), "National Park"
    return match.group("name").strip(), f"National Park{match.group('rest') or ''}".strip()


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
    state = park["state"].removeprefix("AU-")
    found = locate(area, sources)
    if found != state:
        report.add("parks the boundaries place elsewhere (the list's state kept)",
                   f"{place_id}: {found}≠{state}")

    hero, gallery = norway._park_photos(place_id, guide, sources, context.images_dir, report)
    if hero is None:
        report.add("parks without a photograph", place_id)
    official = rules.official_page(guide.get("sources"))

    # The year is the guide's alone. CAPAD's gazettal date is when the land now in a park
    # was last gazetted, which disagreed with the agency's founding year for 11 of 44
    # guided parks; a wrong year would ship as fact, so none stands in for the guide's.
    facts = norway._facts(place_id, guide, report)

    name, designation = split_name(park["name"])
    record_place: dict[str, Any] = {
        "id": place_id,
        "name": name,
        "designation": designation,
        "kind": NATIONAL_PARK_KIND,
        "agency": rules.agency(park.get("agency")),
        "country": COUNTRY,
        "subdivisions": [rules.subdivision(state)],
        "centre": _centre(area),
        "themes": norway._themes(place_id, guide, report),
        "facts": facts,
        "passportRegion": park["passportRegion"],
    }
    if park["passportRegion"] != rules.passport_region(state):
        report.add("parks in another state's passport book", place_id)
    if record_place["agency"] == "stateAgency" and park.get("agency"):
        record_place["managedBy"] = park["agency"]
    if official:
        record_place["officialURL"] = official
    if summary := clean(guide.get("summary")):
        record_place["summary"] = summary
        record_place["summarySource"] = "Unigrids"
    if hero:
        record_place["image"] = hero

    pois = _guide_pois(place_id, guide, poi_registry, report)

    sources_list = []
    for source in guide.get("sources") or []:
        if not isinstance(source, dict) or not (source.get("title") or source.get("url")):
            continue
        entry = {"title": clean(source.get("title")) or source["url"]}
        if source.get("url"):
            entry["url"] = source["url"]
        sources_list.append(entry)

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
    if not any("Protected Areas Database" in line for line in credits):
        credits.append(DEFAULT_CREDITS[1])
    return credits


# MARK: - Points of interest


def _guide_pois(
    place_id: str, guide: dict[str, Any], registry: ids.Registry, report: norway._Report
) -> list[dict[str, Any]]:
    """The guide's sights, ranked in the guide's order, and its visitor centres and
    trailheads."""
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
        poi_id = ids.country_poi_id(registry, "au", slug, f"guide:{place_id}:{name}", name)
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
    """A guide's ``[latitude, longitude]``, if it lies in Australia's box, the island
    territories included."""
    if not isinstance(value, list | tuple) or len(value) != 2:
        return None
    latitude, longitude = value
    if not isinstance(latitude, int | float) or not isinstance(longitude, int | float):
        return None
    if not (-44.0 <= latitude <= -9.0 and 96.0 <= longitude <= 168.5):
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
        if box is None or not _within(box.buffered(reach_km * 1000 + 1), point):
            continue
        if outline.contains(area.polygons, point[1], point[0]):
            return 0.0, park_id
        if reach_km <= 0:
            continue
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
) -> list[dict[str, Any]]:
    """OpenStreetMap's named visitor centres, campgrounds and huts, each given to the park
    it stands in or beside: a campground or hut on the boundary, a visitor centre within
    :data:`VISITOR_CENTRE_REACH_KM`, or within :data:`NAMED_CENTRE_REACH_KM` if its name
    names the park. An information office whose name does not say it is a visitor centre
    is left out, and so is one a guide already lists."""
    found: list[dict[str, Any]] = []
    short_names = {
        park["id"]: split_name(park["name"])[0].lower()
        for park in content.parks() if park["id"] in park_areas
    }
    for element in sources.facilities:
        tags = element.get("tags") or {}
        kind = rules.facility_kind(tags)
        name = re.sub(r"\s+", " ", tags.get("name") or "").strip()
        if kind is None or not name or not rules.is_public(tags):
            continue
        if kind == "visitorCentre" and not rules.is_visitor_centre_name(name):
            continue
        point = rail.point_of(element)
        assert point is not None
        reach = VISITOR_CENTRE_REACH_KM if kind == "visitorCentre" else EDGE_REACH_KM
        nearest = _nearest_park(point, park_areas, reach)
        if kind == "visitorCentre" and nearest is None:
            for park_id, short in short_names.items():
                names = f"{short} national park" in name.lower() or (
                    len(short) > 5 and name.lower().startswith(short)
                )
                if names and _nearest_park(
                    point, {park_id: park_areas[park_id]}, NAMED_CENTRE_REACH_KM
                ):
                    nearest = (0.0, park_id)
        if nearest is None:
            continue
        park_id = nearest[1]
        here = _location(point)
        if any(
            poi["placeID"] == park_id and poi["kind"] in (kind, "sight")
            and rail.metres(point, (poi["location"]["latitude"], poi["location"]["longitude"]))
            <= (SAME_PLACE_M if kind == "visitorCentre" else 100)
            for poi in [*pois, *found]
        ):
            continue
        slug = content.park_slug(park_id)
        poi: dict[str, Any] = {
            "id": ids.country_poi_id(registry, "au", slug, rail.key_of(element), name),
            "placeID": park_id,
            "kind": kind,
            "name": name,
            "location": here,
            "rank": 0,
            "hasStamp": False,
        }
        if summary := rules.facility_summary(tags):
            poi["summary"] = summary
        website = tags.get("website") or tags.get("contact:website") or ""
        if website.startswith(("http://", "https://")):
            poi["url"] = website
        found.append(poi)
    counts: dict[str, int] = {}
    for poi in found:
        counts[poi["kind"]] = counts.get(poi["kind"], 0) + 1
    print(f"    OpenStreetMap facilities in or beside the parks: {counts}")
    return sorted(found, key=lambda poi: (poi["placeID"], poi["kind"], poi["name"], poi["id"]))


def _within(box: geo.BoundingBox, point: tuple[float, float]) -> bool:
    latitude, longitude = point
    return box.south <= latitude <= box.north and box.west <= longitude <= box.east


_COARSE: dict[str, list[Any]] = {}


def _coarse(area: Area) -> list[Any]:
    """The park's outline generalised to about 500 m, for distances in kilometres."""
    if area.key not in _COARSE:
        _COARSE[area.key] = outline.generalise(area.polygons, 0.005) or area.polygons
    return _COARSE[area.key]


# MARK: - Second tier


def _second_tier_place(
    area: Area,
    sources: _Sources,
    registry: ids.Registry,
    report: norway._Report,
    areas_found: dict[str, int],
) -> dict[str, Any] | None:
    """A state or territory national park: named, outlined, dated and measured from
    CAPAD, located by the ABS's boundaries, and described by its Wikipedia lead where it
    has one."""
    name = area.name
    if name is None:
        report.add("left out: CAPAD gives no name", area.key)
        return None
    state = locate(area, sources)
    region = rules.passport_region(state)
    if state is None or region is None:
        report.add("left out: in no state or territory", area.key)
        return None
    if rules.capad_state(area.state, *(area.centre or (None, None))) not in (state, None):
        report.add("state national parks the boundaries place outside CAPAD's state",
                   f"{area.key}→{state}")
    proposed = None
    for candidate in rules.identifier_names(name):
        try:
            proposed = ids.country_place_id("au", "snp", candidate)
            break
        except ids.UnromanisedNameError:
            continue
    if proposed is None:
        report.add("left out: no Latin name to make an identifier from", area.key)
        return None
    place_id = registry.resolve(
        f"capad:{area.key}", proposed, qualifier=ids.romanised_slug(state)
    )
    facts: dict[str, Any] = {}
    hectares, basis = rules.area_hectares(area.parts)
    if hectares is not None and basis is not None:
        facts["areaHectares"] = round(hectares)
        areas_found[basis] = areas_found.get(basis, 0) + 1
    place: dict[str, Any] = {
        "id": place_id,
        "name": name,
        "designation": "National Park",
        "kind": STATE_NATIONAL_PARK_KIND,
        "agency": "stateAgency",
        "country": COUNTRY,
        "subdivisions": [rules.subdivision(state)],
        "centre": _centre(area),
        "facts": facts,
        "passportRegion": region,
    }
    if managed := rules.AUTHORITIES.get(area.authority or ""):
        place["managedBy"] = managed
    key = f"snp:{area.key}"
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


# MARK: - Transport


def _transport(park_areas: dict[str, Area]) -> dict[str, list[Any]] | None:
    """``railLines`` (the long-distance trains, the states' regional services and the
    cities' networks, as OpenStreetMap maps them) and
    ``railStations`` within reach of a park that one of them calls at, or nothing if the
    rail was never read."""
    directory = rawstore.latest(OSM, RAIL_FILE)
    if directory is None:
        print(f"    no raw/{OSM} rail routes: no rail layers this run")
        return None
    routes = {key: route for key, route in rail.read_routes(directory).items()
              if rules.is_passenger_service(route.tags)}
    group_lines(list(routes.values()))
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
        # A station no passenger line calls at is a heritage line's, or out of use.
        if not names:
            without_lines += 1
            continue
        entry = rail.station_entry(station, names)
        entry["country"] = COUNTRY
        stations.append(entry)
    print(
        f"    rail: {len(lines)} passenger lines from {len(belongs)} routes; "
        f"{len(stations)} stations within {rail.STATION_REACH_KM:.0f} km of a park "
        f"({without_lines} with no line left out)"
    )
    return {"railLines": lines, "railStations": stations}


def group_lines(routes: list[rail.Route]) -> None:
    """One line for the services of one line: Melbourne's through-running variants under
    their own line's number, Perth's directions under the line their names open with, and
    a numbered train's two directions (NSW TrainLink's 223 and 224) under the lower
    number, as Canada's VIA trains are paired."""
    from ..ca import assembly as canada

    for route in routes:
        route.tags = rules.line_tags(route.tags)
    canada.pair_directions(routes)


# MARK: - Documents


def _documents(places: list[dict[str, Any]], sources: _Sources) -> dict[str, Any] | None:
    """Each national park's page on its agency's site and the PDFs it links that
    answered."""
    if not sources.documents:
        return None
    result: dict[str, Any] = {}
    rank = {"brochure": 0, "map": 1, "other": 2}
    # A PDF the pages of several parks link is the agency's, for every park (a
    # children's activity booklet), not any one park's.
    linked: dict[str, int] = {}
    for entry in sources.documents.values():
        for document in entry.get("documents") or []:
            linked[document["url"]] = linked.get(document["url"], 0) + 1
    for place in places:
        entry = sources.documents.get(place["id"])
        if place["kind"] != NATIONAL_PARK_KIND or not entry:
            continue
        documents = [
            {**document, "title": title, "kind": rules.document_kind(title, document["url"])}
            for document in entry.get("documents") or []
            if (title := rules.document_title(document["title"]))
            and rules.is_the_parks_document(title) and linked[document["url"]] == 1
        ]
        documents.sort(key=lambda doc: rank[doc["kind"]])
        result[place["id"]] = {"page": entry.get("page"), "documents": documents}
    with_pdf = sum(1 for entry in result.values() if entry["documents"])
    print(f"    documents: {len(result)} park pages, {with_pdf} with a PDF")
    return result
