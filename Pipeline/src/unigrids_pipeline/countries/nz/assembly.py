"""New Zealand's share of the reference dataset.

The 13 national parks with their guides; every conservation and forest park of 5 km² or
more; their outlines; the guides' sights, and DOC's huts, campsites and visitor centres in
and beside each national park; DOC's tracks; the rail stations near the parks and the
passenger lines through them; each park's climate and DOC page with its brochures and maps.

The split of responsibility is Norway's: DOC's Public Conservation Land says what an area
is — its name, outline and recorded area — Stats NZ's regions where it lies, and the
curated guides what Unigrids wrote or chose. Nothing here invents a figure. A value the
sources do not carry is left out, and the app renders it as absent.
"""

from __future__ import annotations

import json
from pathlib import Path
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
from ..no import rules as norway_rules
from ..no import transport as rail
from . import content, rules, wiki
from .fetching import (
    CLIMATE,
    COMMONS,
    DOCUMENTS,
    FACILITIES,
    OSM,
    PCL,
    PHOTOS,
    RAIL_FILE,
    REGIONS,
    STATIONS_FILE,
    WIKIDATA,
    WIKIPEDIA,
    Area,
    left_out,
    national_parks,
    read_areas,
    read_candidates,
    read_layer,
    read_regions,
    second_tier,
    wiki_matches,
)

COUNTRY = "NZ"
AGENCY = "conservationDepartmentNZ"
NATIONAL_PARK = ("National Park", "nationalPark")
CONSERVATION_PARK_KIND = "conservationPark"

POI_KINDS = frozenset({"sight", "viewpoint", "visitorCentre", "entrance", "trailhead"})
RANKED_KINDS = frozenset({"sight", "viewpoint"})

# How far outside a park a DOC visitor centre may stand and still be that park's: the
# centres sit in the towns at a park's edge (St Arnaud, Mount Cook Village, Oban).
VISITOR_CENTRE_REACH_KM = 10.0
# A guide's visitor centre this close to DOC's is the same building, and the guide's note
# is kept.
SAME_PLACE_M = 500.0

DEFAULT_CREDITS = [
    "Text written for Unigrids. Facts checked against the Department of Conservation's "
    "pages and the sources below.",
    "Park outline: Public Conservation Land, Department of Conservation, CC BY 4.0 "
    "(Crown Copyright: Department of Conservation Te Papa Atawhai). The outline is "
    "simplified by Unigrids.",
]


def assemble(context: BuildContext) -> Contribution:
    """Every New Zealand place, point of interest, outline, guide and layer, from the raw
    store and ``content/countries/nz/``. Offline by design: ``context.online`` only lets
    trails and elevation tiles that were not fetched be fetched now."""
    pcl_dir = rawstore.latest(PCL, "national-parks.geojson")
    if pcl_dir is None:
        raise SystemExit(f"no raw/{PCL} yet: run New Zealand's fetch with network")
    print(f"    reading raw/{pcl_dir.parent.name}/{PCL}")
    areas = read_areas(pcl_dir)
    sources = _Sources()
    report = norway._Report()

    place_registry = ids.country_registry("nz", "places")
    poi_registry = ids.country_registry("nz", "pois")

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
        place, guide, park_pois = _national_park(
            park, area, sources, poi_registry, context, report
        )
        boundaries[place["id"]] = outline_entry
        place["extent"] = extent(outline_entry["bbox"])
        places.append(place)
        pois.extend(park_pois)
        guides[place["id"]] = guide
    pois.extend(_visitor_centres(park_areas, pois, sources, poi_registry, report))

    sources.matches = wiki_matches(areas, sources.candidates)
    for area in second_tier(areas):
        outline_entry = encode_outline(area.polygons, OTHER_TOLERANCE)
        if not outline_entry:
            report.add("left out: no outline at the map's scale", area.napalis_id)
            continue
        place = _second_tier_place(area, sources, place_registry, report)
        if place is None:
            continue
        boundaries[place["id"]] = outline_entry
        place["extent"] = extent(outline_entry["bbox"])
        places.append(place)
    for area in left_out(areas):
        report.add("conservation park records under 5 km²", f"{area.name} ({area.napalis_id})")

    # Trails from DOC Tracks (OpenStreetMap where it has none), measured as the US's are;
    # and each park's lowest and highest ground, from Copernicus GLO-30.
    trail_registry = ids.country_registry("nz", "trails")
    pois_by_park: dict[str, list[dict[str, Any]]] = {}
    for poi in pois:
        pois_by_park.setdefault(poi["placeID"], []).append(poi)
    trails = abroad_trails.build(
        "nz", parks, park_outlines, pois_by_park, online=context.online, registry=trail_registry
    )
    abroad_elevation.attach_extremes(places, park_outlines, online=context.online)

    _zone(places, report)
    _report_te_urewera(pcl_dir)
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
        expects_summary={place["id"] for place in places if place["kind"] == "nationalPark"},
        trails=trails,
        registries=[place_registry, poi_registry, trail_registry],
    )


# MARK: - Raw sources


class _Sources:
    """The newest fetched copy of each source the build reads, or nothing."""

    def __init__(self) -> None:
        regions_dir = rawstore.latest(REGIONS, "regions.geojson")
        self.regions = (
            norway_rules.Counties(read_regions(regions_dir / "regions.geojson"))
            if regions_dir else None
        )
        if self.regions is None:
            print(f"    no raw/{REGIONS}: places carry no regions and the second tier none")
        self.candidates = read_candidates(rawstore.latest(WIKIDATA, "candidates.json"))
        self.matches: dict[str, dict[str, Any]] = {}
        self.summaries = norway._json(rawstore.latest(WIKIPEDIA, "summaries.json"),
                                      "summaries.json")
        self.licences = norway._json(rawstore.latest(COMMONS, "licences.json"), "licences.json")
        self.photos = rawstore.latest(PHOTOS)
        self.documents = norway._json(rawstore.latest(DOCUMENTS, "links.json"), "links.json")
        facilities = rawstore.latest(FACILITIES)
        self.huts = [f for f in read_layer(facilities, "huts.geojson") if _usable(f)]
        self.campsites = [f for f in read_layer(facilities, "campsites.geojson") if _usable(f)]
        self.huts_web = _by_asset(read_layer(facilities, "huts-web.geojson"))
        self.campsites_web = _by_asset(read_layer(facilities, "campsites-web.geojson"))
        self.visitor_centres = [
            feature for feature in read_layer(facilities, "visitor-centres.geojson")
            if (feature.get("properties") or {}).get("IsActive") in (1, True, "1", None)
            and _point(feature) is not None
        ]
        self.climate = rawstore.latest(CLIMATE)


def _usable(feature: dict[str, Any]) -> bool:
    properties = feature.get("properties") or {}
    return (
        rules.is_open_to_the_public(properties)
        and bool(clean(properties.get("TechObjectName")))
        and _point(feature) is not None
    )


def _by_asset(features: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    """The website layer's records by asset number, the asset layers' ``SortField``."""
    found: dict[str, dict[str, Any]] = {}
    for feature in features:
        properties = feature.get("properties") or {}
        if (asset := properties.get("assetId")) is not None:
            found[str(int(asset))] = properties
    return found


def _point(feature: dict[str, Any]) -> tuple[float, float] | None:
    """``(latitude, longitude)`` of a point feature."""
    geometry = feature.get("geometry") or {}
    coordinates = geometry.get("coordinates") if geometry.get("type") == "Point" else None
    if not coordinates or len(coordinates) < 2:
        return None
    longitude, latitude = float(coordinates[0]), float(coordinates[1])
    return latitude, longitude


# MARK: - Where a place is


def _locate(area: Area, sources: _Sources) -> list[str]:
    """The place's regions, largest share first, as ``NZ-XXX`` codes."""
    if sources.regions is None:
        return []
    shares = sources.regions.shares(area.polygons)
    ordered = sorted(shares, key=lambda code: (-shares[code], code))
    return [rules.subdivision(code) for code in ordered]


def _zone(places: list[dict[str, Any]], report: norway._Report) -> None:
    """Each place's zone at its centre, held to the two New Zealand keeps: the Chathams'
    own and the mainland's."""
    assign_time_zones(places)
    for place in places:
        codes = [code.removeprefix("NZ-") for code in place.get("subdivisions") or []]
        expected = rules.time_zone(codes)
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
    subdivisions = _locate(area, sources)
    if not subdivisions:
        report.add("parks in no region", place_id)

    hero, gallery = norway._park_photos(place_id, guide, sources, context.images_dir, report)
    if hero is None:
        report.add("parks without a photograph", place_id)
    links = sources.documents.get(place_id) or {}
    official = park.get("docPage") or links.get("page")

    place: dict[str, Any] = {
        "id": place_id,
        "name": park["name"],
        "designation": NATIONAL_PARK[0],
        "kind": NATIONAL_PARK[1],
        "agency": AGENCY,
        "country": COUNTRY,
        "subdivisions": subdivisions,
        "centre": _centre(area),
        "themes": norway._themes(place_id, guide, report),
        "facts": norway._facts(place_id, guide, report),
        "passportRegion": park["passportRegion"],
    }
    # A guide's area is the park's own page's; where the guide gives none, DOC's recorded
    # area for the land is the next authority, never the drawing's measured area.
    if "areaHectares" not in place["facts"] and (hectares := area.recorded_hectares):
        place["facts"]["areaHectares"] = round(hectares)
    if park["passportRegion"] not in rules.PASSPORT_REGIONS:
        report.add("parks with an unknown passport region", place_id)
    if official:
        place["officialURL"] = official
    if summary := clean(guide.get("summary")):
        place["summary"] = summary
        place["summarySource"] = "Unigrids"
    if hero:
        place["image"] = hero
    names = [
        {"language": entry["language"], "text": entry["text"]}
        for entry in park.get("localNames") or []
        if isinstance(entry, dict) and entry.get("language") and entry.get("text")
    ]
    if names:
        place["localNames"] = names
    if reached_by := clean(park.get("reachedBy")):
        place["reachedBy"] = reached_by

    pois = _guide_pois(place_id, guide, poi_registry, report)
    pois.extend(_facilities(place_id, area, sources, poi_registry))

    sources_list = []
    for source in guide.get("sources") or []:
        if not isinstance(source, dict) or not (source.get("title") or source.get("url")):
            continue
        entry = {"title": clean(source.get("title")) or source["url"]}
        if source.get("url"):
            entry["url"] = source["url"]
        sources_list.append(entry)
    if official and not any("doc.govt.nz" in (s.get("url") or "") for s in sources_list):
        sources_list.append({
            "title": f"{park['name']} National Park — Department of Conservation",
            "url": official,
        })

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
    return place, record, pois


def _credits(guide: dict[str, Any]) -> list[str]:
    """The guide's own credits, or the default; either way ending with the credit CC BY
    asks for, which says the outline was changed (simplified) by Unigrids."""
    credits = norway._strings(guide.get("credits")) or DEFAULT_CREDITS[:1]
    if not any("Public Conservation Land" in line for line in credits):
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
        poi_id = ids.country_poi_id(registry, "nz", slug, f"guide:{place_id}:{name}", name)
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
    """A guide's ``[latitude, longitude]``, if it lies in New Zealand's main islands,
    Rakiura or the Chathams."""
    if not isinstance(value, list | tuple) or len(value) != 2:
        return None
    latitude, longitude = value
    if not isinstance(latitude, int | float) or not isinstance(longitude, int | float):
        return None
    mainland = -47.5 <= latitude <= -34.0 and 166.0 <= longitude <= 179.0
    chathams = -44.6 <= latitude <= -43.4 and -177.2 <= longitude <= -175.8
    if not (mainland or chathams):
        return None
    return {"latitude": round(float(latitude), 5), "longitude": round(float(longitude), 5)}


def _asset_key(properties: dict[str, Any]) -> tuple[str, str | None]:
    """The registry key of a DOC asset — its asset number, else its site code — and the
    asset number, by which the website layer knows it."""
    sort = properties.get("SortField")
    if isinstance(sort, int | float):
        return f"doc:asset/{int(sort)}", str(int(sort))
    return f"doc:floc/{properties.get('FlocID') or properties.get('GlobalID')}", None


def _facilities(
    place_id: str, area: Area, sources: _Sources, registry: ids.Registry
) -> list[dict[str, Any]]:
    """DOC's open, public huts and campsites inside the park's own outline."""
    box = area.box
    if box is None:
        return []
    slug = content.park_slug(place_id)
    pois = []
    for kind, features, web, describe in (
        ("hut", sources.huts, sources.huts_web, rules.hut_summary),
        ("campground", sources.campsites, sources.campsites_web, rules.campsite_summary),
    ):
        for feature in features:
            point = _point(feature)
            assert point is not None
            if not _within(box, point) or not outline.contains(area.polygons, point[1], point[0]):
                continue
            properties = feature.get("properties") or {}
            name = clean(properties.get("TechObjectName")) or ""
            key, asset = _asset_key(properties)
            page = web.get(asset or "") or {}
            poi: dict[str, Any] = {
                "id": ids.country_poi_id(registry, "nz", slug, key, name),
                "placeID": place_id,
                "kind": kind,
                "name": name,
                "location": {"latitude": round(point[0], 5), "longitude": round(point[1], 5)},
                "rank": 0,
                "hasStamp": False,
            }
            if summary := describe(properties, page):
                poi["summary"] = summary
            link = page.get("staticLink") or ""
            if link.startswith("https://www.doc.govt.nz/"):
                poi["url"] = link
            pois.append(poi)
    return sorted(pois, key=lambda poi: (poi["kind"], poi["name"], poi["id"]))


def _visitor_centres(
    park_areas: dict[str, Area],
    pois: list[dict[str, Any]],
    sources: _Sources,
    registry: ids.Registry,
    report: norway._Report,
) -> list[dict[str, Any]]:
    """DOC's visitor centres, each given to the national park it names, or stands in or
    beside (within :data:`VISITOR_CENTRE_REACH_KM`); one the guide already lists is left to the
    guide."""
    found = []
    for feature in sources.visitor_centres:
        properties = feature.get("properties") or {}
        point = _point(feature)
        assert point is not None
        name = clean(properties.get("FullNameLabel")) or clean(properties.get("Name")) or ""
        if not name:
            continue
        nearest: tuple[float, str] | None = None
        for park_id, area in park_areas.items():
            box = area.box
            if box is None or not _within(box.buffered(VISITOR_CENTRE_REACH_KM * 1000), point):
                continue
            distance = rail.distance_to_outline_km(point, _coarse(area))
            if distance <= VISITOR_CENTRE_REACH_KM and (nearest is None or distance < nearest[0]):
                nearest = (distance, park_id)
        # A centre that names its park ("Tititea / Mount Aspiring National Park Visitor
        # Centre", in Wānaka) is that park's, however far the town is from the boundary.
        for park in content.parks():
            if park["id"] in park_areas and f"{park['name']} National Park".lower() in name.lower():
                nearest = (0.0, park["id"])
        if nearest is None:
            report.add("DOC visitor centres near no national park", name)
            continue
        park_id = nearest[1]
        listed = any(
            poi["placeID"] == park_id and poi["kind"] == "visitorCentre"
            and rail.metres(point, (poi["location"]["latitude"], poi["location"]["longitude"]))
            <= SAME_PLACE_M
            for poi in pois
        )
        if listed:
            continue
        key = f"doc:office/{properties.get('OfficeID') or properties.get('CODE')}"
        poi: dict[str, Any] = {
            "id": ids.country_poi_id(registry, "nz", content.park_slug(park_id), key, name),
            "placeID": park_id,
            "kind": "visitorCentre",
            "name": name,
            "location": {"latitude": round(point[0], 5), "longitude": round(point[1], 5)},
            "rank": 0,
            "hasStamp": False,
        }
        if town := clean(properties.get("Town")):
            poi["summary"] = f"Department of Conservation visitor centre, {town}"
        found.append(poi)
    return sorted(found, key=lambda poi: (poi["placeID"], poi["name"]))


def _within(box: geo.BoundingBox, point: tuple[float, float]) -> bool:
    latitude, longitude = point
    return box.south <= latitude <= box.north and box.west <= longitude <= box.east


_COARSE: dict[str, list[Any]] = {}


def _coarse(area: Area) -> list[Any]:
    """The park's outline generalised to about 500 m, for distances in kilometres."""
    if area.napalis_id not in _COARSE:
        _COARSE[area.napalis_id] = outline.generalise(area.polygons, 0.005) or area.polygons
    return _COARSE[area.napalis_id]


# MARK: - Second tier


def _second_tier_place(
    area: Area, sources: _Sources, registry: ids.Registry, report: norway._Report
) -> dict[str, Any] | None:
    """A conservation or forest park: named, outlined and measured from Public
    Conservation Land, located by Stats NZ's regions, and described by its Wikipedia
    lead where it has one."""
    subdivisions = _locate(area, sources)
    region = rules.passport_region(subdivisions[0].removeprefix("NZ-")) if subdivisions else None
    if not subdivisions or not region:
        report.add("left out: in no region with a passport book", f"{area.napalis_id} {area.name}")
        return None
    name, designation = rules.display_name(area.name)
    proposed = ids.country_place_id("nz", "cp", name)
    region_name = next(
        (title for code, title in rules.REGIONS.values() if f"NZ-{code}" == subdivisions[0]),
        "",
    )
    place_id = registry.resolve(
        f"napalis:{area.napalis_id}",
        proposed,
        qualifier=ids.romanised_slug(region_name) if region_name else None,
    )
    facts: dict[str, Any] = {}
    if (hectares := area.recorded_hectares) is not None:
        facts["areaHectares"] = round(hectares)
    place: dict[str, Any] = {
        "id": place_id,
        "name": name,
        "designation": designation,
        "kind": CONSERVATION_PARK_KIND,
        "agency": AGENCY,
        "country": COUNTRY,
        "subdivisions": subdivisions,
        "centre": _centre(area),
        "facts": facts,
        "passportRegion": region,
    }
    item = sources.matches.get(area.napalis_id)
    summary = sources.summaries.get(area.napalis_id) if item else None
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


def _report_te_urewera(pcl_dir: Path) -> None:
    counts = norway._json(pcl_dir, "counts.json")
    if counts:
        print(
            f"    Public Conservation Land: {counts.get('nationalParks')} national parks, "
            f"{counts.get('conservationParks')} conservation park records, "
            f"{counts.get('teUrewera') or 0} named Te Urewera (not conservation land since 2014)"
        )


# MARK: - Transport


def _transport(park_areas: dict[str, Area]) -> dict[str, list[Any]] | None:
    """``railLines`` and ``railStations``, or nothing if the rail was never read."""
    directory = rawstore.latest(OSM, RAIL_FILE)
    if directory is None:
        print(f"    no raw/{OSM} rail routes: no rail layers this run")
        return None
    routes = rail.read_routes(directory)
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


# MARK: - Documents


def _document_kind(title: str, url: str) -> str:
    text = f"{title} {url.rsplit('/', 1)[-1]}".lower()
    if "brochure" in text or "leaflet" in text or "guide" in text:
        return "brochure"
    if "map" in text:
        return "map"
    return "other"


def _documents(places: list[dict[str, Any]], sources: _Sources) -> dict[str, Any] | None:
    """Each national park's page on doc.govt.nz and the PDFs it links that answered."""
    if not sources.documents:
        return None
    result: dict[str, Any] = {}
    rank = {"brochure": 0, "map": 1, "other": 2}
    for place in places:
        entry = sources.documents.get(place["id"])
        if place["kind"] != "nationalPark" or not entry:
            continue
        documents = [
            {**document, "kind": _document_kind(document["title"], document["url"])}
            for document in entry.get("documents") or []
        ]
        documents.sort(key=lambda doc: rank[doc["kind"]])
        result[place["id"]] = {"page": entry.get("page"), "documents": documents}
    with_pdf = sum(1 for entry in result.values() if entry["documents"])
    print(f"    documents: {len(result)} park pages, {with_pdf} with a PDF")
    return result
