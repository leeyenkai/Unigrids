"""Canada's rules and records, on small fixtures and no network.

The rules are the ones a wrong answer would ship quietly: which province, passport book and
zone a place belongs to, which CPCAD records make a park and what the park is called, how
Parks Canada's trail ratings, facilities and attendance read, and that every identifier
goes through a registry keyed on its source's own id — with no US fallback anywhere.
"""

from __future__ import annotations

import json

import pytest

from unigrids_pipeline import config, countries, ids
from unigrids_pipeline.countries import BuildContext
from unigrids_pipeline.countries.abroad import outlines as abroad_outlines
from unigrids_pipeline.countries.abroad import packs as abroad_packs
from unigrids_pipeline.countries.abroad import trails as abroad_trails
from unigrids_pipeline.countries.ca import (
    assembly,
    content,
    fetching,
    pctrails,
    rules,
    wiki,
)
from unigrids_pipeline.sources import osm_pbf

# MARK: - The park list


def test_the_park_list_holds_the_forty_eight_parks():
    parks = content.parks()
    assert len(parks) == 48
    assert len({park["id"] for park in parks}) == 48
    assert len({park["name"] for park in parks}) == 48
    assert len({park["cpcadParentId"] for park in parks}) == 48
    assert all(park["id"].startswith("ca-np-") for park in parks)
    assert all(park["pcPage"].startswith("https://parks.canada.ca/pn-np/") for park in parks)
    assert all(
        any(name["language"] == "fr" for name in park["localNames"]) for park in parks
    )
    rouge = next(park for park in parks if park["id"] == "ca-np-rouge")
    assert rouge["designation"] == "National Urban Park"
    assert "attendancePlace" not in rouge


def test_every_park_is_in_its_passport_book():
    regions: dict[str, set[str]] = {}
    for park in content.parks():
        regions.setdefault(park["passportRegion"], set()).add(park["id"])
    assert set(regions) == rules.PASSPORT_REGIONS
    assert {region: len(members) for region, members in regions.items()} == {
        "mountainsAndPacific": 11, "north": 14, "prairies": 4, "ontario": 6, "quebec": 3,
        "atlantic": 10,
    }
    # Wood Buffalo lies mostly in Alberta and is filed with the North.
    assert "ca-np-wood-buffalo" in regions["north"]
    assert {"ca-np-la-mauricie", "ca-np-forillon", "ca-np-mingan-archipelago"} == (
        regions["quebec"]
    )


def test_fly_in_parks_say_how_they_are_reached():
    reached = {park["id"] for park in content.parks() if park.get("reachedBy")}
    assert {"ca-np-quttinirpaaq", "ca-np-sable-island", "ca-np-gwaii-haanas",
            "ca-np-torngat-mountains", "ca-np-wapusk"} <= reached
    assert "ca-np-banff" not in reached
    torngat = next(park for park in content.parks() if park["id"] == "ca-np-torngat-mountains")
    assert {"language": "iu", "text": "Tongait KakKasuangita SilakKijapvinga"} in (
        torngat["localNames"]
    )


# MARK: - Identifiers


def test_canadian_identifiers_carry_the_country():
    assert ids.PLACE_NAMESPACES["ca"] == ("np", "mca", "pp")
    assert ids.country_place_id("ca", "pp", "Wells Gray") == "ca-pp-wells-gray"
    assert ids.country_place_id("ca", "mca", "Fathom Five") == "ca-mca-fathom-five"
    with pytest.raises(ValueError):
        ids.country_place_id("ca", "cp", "Wells Gray")
    for identifier in ("ca-np-banff", "poi-ca-banff-x", "trail-ca-banff-x", "ca-pp-x"):
        assert ids.country_of(identifier) == "ca"


def test_a_provincial_park_is_pinned_to_its_cpcad_parent(tmp_path):
    registry = ids.Registry(tmp_path / "places.json")
    first = registry.resolve("cpcad:471000076", "ca-pp-cypress-hills")
    assert first == "ca-pp-cypress-hills"
    assert registry.resolve("cpcad:471000076", "ca-pp-renamed") == first
    # Alberta's half of the interprovincial park is another place.
    assert registry.resolve("cpcad:480001014", "ca-pp-cypress-hills", qualifier="alberta") == (
        "ca-pp-cypress-hills-alberta"
    )


# MARK: - Provinces and zones


@pytest.mark.parametrize(
    ("loc", "iso", "book"),
    [
        (1, "AB", "mountainsAndPacific"), (2, "BC", "mountainsAndPacific"),
        (3, "MB", "prairies"), (12, "SK", "prairies"), (9, "ON", "ontario"),
        (11, "QC", "quebec"), (4, "NB", "atlantic"), (5, "NL", "atlantic"),
        (7, "NS", "atlantic"), (10, "PE", "atlantic"), (6, "NT", "north"),
        (8, "NU", "north"), (13, "YT", "north"),
    ],
)
def test_every_location_has_its_province_and_book(loc, iso, book):
    assert rules.iso_code(loc) == iso
    assert rules.subdivision(iso) == f"CA-{iso}"
    assert rules.passport_region(iso) == book


def test_a_marine_location_names_no_province():
    assert rules.iso_code(16) is None
    assert rules.iso_code(None) is None


def test_a_place_keeps_its_own_canadian_zone_and_only_that():
    # Nunavut's parks keep the zone where they lie, not Iqaluit's.
    assert rules.time_zone("America/Rankin_Inlet", ["NU"]) == "America/Rankin_Inlet"
    assert rules.time_zone("America/Resolute", ["NU"]) == "America/Resolute"
    assert rules.time_zone("America/Edmonton", ["BC"]) == "America/Edmonton"  # Yoho
    # A centre at sea answers an ocean's zone; the province's stands in.
    assert rules.time_zone("Etc/GMT+4", ["NS"]) == "America/Halifax"
    assert rules.time_zone(None, ["NL"]) == "America/St_Johns"
    assert rules.time_zone(None, []) is None


# MARK: - CPCAD


@pytest.mark.parametrize(
    ("name", "type_e", "shown", "designation"),
    [
        ("Cypress Hills Provincial Park", "Provincial Park", "Cypress Hills", "Provincial Park"),
        ("CAPE SCOTT PARK", "A - Park", "Cape Scott", "Provincial Park"),
        ("HEIGHT OF THE ROCKIES PARK", "A - Park", "Height of the Rockies", "Provincial Park"),
        ("Frontenac National Park (Québec)", "Quebec's national park", "Frontenac",
         "Provincial Park"),
        ("Brightsand River Provincial Park (Waterway Class)", "Provincial Park",
         "Brightsand River", "Provincial Park"),
        ("Kakwa Wildland Provincial Park", "Wildland Provincial Park", "Kakwa",
         "Wildland Provincial Park"),
        ("Kitaskino Nuwenëné Wildland", "Wildland Provincial Park", "Kitaskino Nuwenëné",
         "Wildland Provincial Park"),
        ("Willmore Wilderness Park", "Wilderness Park", "Willmore", "Wilderness Park"),
        ("Tombstone", "Territorial Park", "Tombstone", "Territorial Park"),
        ("Katannilik Territorial Park", "Territorial Park", "Katannilik", "Territorial Park"),
        ("KHUTZEYMATEEN PARK [A.K.A. KHUTZEYMATEEN/K'TZIM-A-DEEN GRIZZLY SANCTUARY]",
         "A - Park", "Khutzeymateen", "Provincial Park"),
        ("FOCH-GILTTOYEES PARK", "A - Park", "Foch-Gilttoyees", "Provincial Park"),
    ],
)
def test_a_provincial_park_is_named_and_labelled_provincial(name, type_e, shown, designation):
    assert rules.display_name(name, type_e) == (shown, designation)


def test_a_dual_name_without_a_latin_form_makes_its_identifier_from_the_other():
    names = rules.identifier_names("Mᑫuqʷin/Brooks Peninsula", "Provincial Park")
    assert names[-1] == "Brooks Peninsula"
    with pytest.raises(ids.UnromanisedNameError):
        ids.romanised_slug(names[0])
    assert rules.identifier_names("Castle", "Wildland Provincial Park") == ["Castle Wildland"]


def test_a_provincial_park_counts_by_its_official_area():
    rows = [
        {"PARENT_ID": 1, "TYPE_E": "Provincial Park", "O_AREA_HA": 6000.0, "STATUS": 1},
        {"PARENT_ID": 1, "TYPE_E": "Provincial Park", "O_AREA_HA": 5000.0, "STATUS": 1},
        {"PARENT_ID": 2, "TYPE_E": "A - Park", "O_AREA_HA": 9999.0, "STATUS": 1},
        {"PARENT_ID": 3, "TYPE_E": "Conservation Reserve", "O_AREA_HA": 90000.0, "STATUS": 1},
        {"PARENT_ID": 4, "TYPE_E": "Provincial Park", "O_AREA_HA": 90000.0, "STATUS": 0},
        {"PARENT_ID": 5, "TYPE_E": "Quebec's national park", "O_AREA_HA": 15650.0, "STATUS": 1},
    ]
    assert fetching.provincial_parents(rows) == [1, 5]
    # The SQL the service is asked carries the apostrophe escaped.
    assert "'Quebec''s national park'" in fetching.provincial_where()


def _record(parent, name, type_e, loc, ring, hectares, *, provider=71, zone=None, status=1):
    return {
        "type": "Feature",
        "geometry": {"type": "Polygon", "coordinates": [[*ring, ring[0]]]},
        "properties": {
            "OBJECTID": zone or parent, "NAME_E": name, "NAME_F": name, "TYPE_E": type_e,
            "LOC": loc, "O_AREA_HA": hectares, "PARENT_ID": parent, "ZONE_ID": zone or parent,
            "PROVIDER": provider, "STATUS": status,
        },
    }


def _ring(west, south, size):
    return [[west, south], [west + size, south], [west + size, south + size], [west, south + size]]


def _collection(*features):
    return {"type": "FeatureCollection", "features": list(features)}


def test_a_park_is_every_record_of_its_parent_and_nothing_else(tmp_path):
    (tmp_path / "national-parks.geojson").write_text(json.dumps(_collection(
        _record(719700000, "Wood Buffalo National Park Of Canada", "National Park", 1,
                _ring(-113.0, 58.5, 1.0), 3564211),
        _record(719700000, "Wood Buffalo National Park Of Canada", "National Park", 6,
                _ring(-113.0, 59.6, 0.5), 913621, zone=719700010),
        _record(714320000, "Gulf Islands National Park Reserve Of Canada",
                "National Park Reserve", 2, _ring(-123.3, 48.7, 0.1), 2551),
        _record(714320000, "Gulf Islands National Park Reserve Of Canada",
                "Program support lands and waters", 2, _ring(-123.1, 48.7, 0.05), 48,
                zone=714320002),
    )))
    (tmp_path / "provincial-parks.geojson").write_text(json.dumps(_collection(
        _record(600000100, "Ni'iinlii Njik (Fishing Branch)", "Territorial Park", 13,
                _ring(-139.5, 66.2, 0.1), 16970, provider=60),
        _record(600002600, "Ni'iinlii Njik (Fishing Branch)", "Territorial Park", 13,
                _ring(-139.8, 66.0, 0.6), 521700, provider=60),
        _record(471000076, "Cypress Hills Provincial Park", "Provincial Park", 12,
                _ring(-109.9, 49.6, 0.1), 18370.9, provider=47),
        _record(480001014, "Cypress Hills Provincial Park", "Provincial Park", 1,
                _ring(-110.2, 49.6, 0.2), 20865.6, provider=48),
    )))
    areas = fetching.read_areas(tmp_path)
    buffalo = areas["np:719700000"]
    assert len(buffalo.polygons) == 2
    assert buffalo.subdivisions() == ["CA-AB", "CA-NT"]
    assert buffalo.official_hectares == 4477832
    assert len(areas["np:714320000"].parts) == 1  # the program-support lands are not the park
    # One territorial park under two parents is one place; a name shared across a
    # provincial border is two.
    assert "pp:600002600" not in areas and len(areas["pp:600000100"].parts) == 2
    assert {"pp:471000076", "pp:480001014"} <= set(areas)
    assert [area.key for area in fetching.second_tier(areas)] == [
        471000076, 480001014, 600000100,
    ]


def test_outlines_for_packs_join_a_parks_records_by_parent():
    features = [
        _record(714900000, "Kejimkujik", "National Park", 7, _ring(-65.4, 44.2, 0.3), 38145.7),
        _record(714900000, "Kejimkujik", "National Park", 7, _ring(-64.9, 43.8, 0.1), 2089,
                zone=714901000),
        _record(718100000, "Saguenay-St. Lawrence Marine Park", "Marine Park", 11,
                _ring(-69.7, 48.0, 0.3), 124600, provider=24),
    ]
    found = abroad_outlines.cpcad_park_polygons(
        features, {714900000: "ca-np-kejimkujik", 718100000: "x"}
    )
    assert set(found) == {"ca-np-kejimkujik"} and len(found["ca-np-kejimkujik"]) == 2


# MARK: - Trails


@pytest.mark.parametrize(
    ("code", "grade", "band"),
    [(1, "Easy", "easy"), (2, "Moderate", "moderate"), (3, "Difficult", "strenuous"),
     (4, "Most difficult", "veryStrenuous"), (9, None, None), (None, None, None)],
)
def test_parks_canadas_ratings_read_into_the_bands(code, grade, band):
    assert rules.difficulty(code) == grade
    assert rules.band(grade) == band


def test_a_rating_is_a_published_grade():
    grade = rules.trail_grade("Difficult")
    assert grade == {
        "system": "parksCanadaDifficulty", "grade": "Difficult",
        "publisher": "Parks Canada", "sourceURL": rules.TRAILS_DATASET_URL,
    }


def _trail(object_id, name, line, *, activity=100, summer=2, section=4):
    return {
        "type": "Feature",
        "geometry": {"type": "LineString", "coordinates": line},
        "properties": {
            "OBJECTID": object_id, "Name_Official_e": name, "General_Activity": activity,
            "Summer_Classification_Été": summer, "Section_Type": section,
        },
    }


@pytest.fixture
def trail_features():
    ink = [[-115.85, 51.25], [-115.84, 51.26], [-115.83, 51.27]]
    ink_on = [[-115.83, 51.27], [-115.82, 51.28], [-115.81, 51.29]]
    return [
        _trail(1, "Ink Pots", ink),
        _trail(2, "Ink Pots", ink, activity=1300),  # the same stretch, for riders
        _trail(3, "Ink Pots", ink, activity=1800),  # and for snowshoes
        _trail(4, "Ink Pots", ink_on),
        _trail(5, "Lakeshore", [[-115.60, 51.10], [-115.59, 51.11], [-115.58, 51.12]], summer=1),
        _trail(6, "Lakeshore", [[-115.20, 51.60], [-115.19, 51.61], [-115.18, 51.62]], summer=3),
        _trail(7, "Winter Loop", [[-115.5, 51.2], [-115.49, 51.21]], activity=1600),
        _trail(8, None, [[-115.4, 51.3], [-115.39, 51.31]]),
        _trail(9, "Gondola", [[-115.4, 51.4], [-115.39, 51.41]], section=8),
        _trail(10, "Far Away", [[-100.0, 49.0], [-100.01, 49.01]]),
    ]


def _banff():
    return [[[(-116.5, 50.7), (-115.0, 50.7), (-115.0, 52.2), (-116.5, 52.2)]]]


def test_hiking_records_join_by_name_and_closeness(trail_features):
    park = {"id": "ca-np-banff"}
    found = pctrails.routes(park, trail_features, _banff())
    assert [(route.name, len(route.segments)) for route in found] == [
        ("Ink Pots", 2), ("Lakeshore", 1), ("Lakeshore", 1),
    ]
    ink = found[0]
    assert ink.key == "parkscanada:banff/ink-pots" and ink.source == "parksCanada"
    assert ink.uses == "Hike, Horse"
    assert ink.extra[pctrails.GRADE_KEY]["grade"] == "Moderate"
    # Two trails of one name far apart stay two, the second keyed by where it lies.
    shores = [route for route in found if route.name == "Lakeshore"]
    assert shores[0].key == "parkscanada:banff/lakeshore"
    assert shores[1].key.startswith("parkscanada:banff/lakeshore@")
    assert {route.extra[pctrails.GRADE_KEY]["grade"] for route in shores} == {"Easy", "Difficult"}


def test_records_that_disagree_leave_the_rating_unsaid():
    records = [{"Summer_Classification_Été": 1}, {"Summer_Classification_Été": 3}]
    assert pctrails.agreed_difficulty(records) is None
    assert pctrails.agreed_difficulty(records[:1]) == "Easy"
    assert pctrails.agreed_difficulty([{"Summer_Classification_Été": None}]) is None


def test_a_parks_canada_trail_is_measured_into_a_record_with_its_rating(trail_features, tmp_path):
    park = {"id": "ca-np-banff"}
    route = pctrails.routes(park, trail_features, _banff())[0]
    registry = ids.Registry(tmp_path / "trails.json")
    record = abroad_trails.trail_record("ca", park, route, lambda lon, lat: None, [], [],
                                        registry)
    assert record is not None
    assert record["id"] == "trail-ca-banff-ink-pots"
    assert record["source"] == "parksCanada" and record["uses"] == "Hike, Horse"
    assert record["publishedGrade"]["system"] == "parksCanadaDifficulty"
    assert registry.owner(record["id"]) == "parkscanada:banff/ink-pots"


def test_a_thinly_covered_park_takes_openstreetmaps_trails_beside_its_own():
    own = [abroad_trails.Route(key="parkscanada:jasper/a", name="Valley of the Five Lakes",
                               latin_name=None, source="parksCanada")]
    osm = [
        abroad_trails.Route(key="osm:way/1", name="Valley of the Five Lakes", latin_name=None,
                            source="osm"),
        abroad_trails.Route(key="osm:way/2", name="Maligne Canyon", latin_name=None,
                            source="osm"),
    ]
    assert abroad_trails.is_thin("ca", own) and not abroad_trails.is_thin("nz", own)
    assert abroad_trails.is_thin("nz", [])
    assert [route.key for route in abroad_trails.with_osm(own, osm)] == [
        "osm:way/2", "parkscanada:jasper/a",
    ]


# MARK: - Facilities and attendance


def test_facilities_read_as_the_points_a_visitor_uses():
    assert rules.facility_kind({"Facility_Type_Installation": 7002}) == "visitorCentre"
    assert rules.facility_kind({"Facility_Type_Installation": 1001}) == "campground"
    assert rules.facility_kind({"Facility_Type_Installation": 3000,
                                "Name_e": "Sawback Lake Backcountry Campground"}) == "campground"
    assert rules.facility_kind({"Facility_Type_Installation": 3000,
                                "Name_e": "Bryant Creek Shelter"}) == "hut"
    assert rules.facility_kind({"Facility_Type_Installation": 3001}) == "hut"
    assert rules.facility_kind({"Facility_Type_Installation": 1014}) is None
    sites = rules.accommodation_counts([
        {"Accommodation_Type": 1}, {"Accommodation_Type": 3}, {"Accommodation_Type": 1},
        {"Accommodation_Type": None},
    ])
    assert sites == {"Camping": 2, "oTENTik": 1}
    assert rules.facility_summary({"Facility_Type_Installation": 1001}, sites) == (
        "Front-country campground · 2 sites · 1 oTENTik"
    )
    assert rules.normal("Two Jack Main Campground") == rules.normal("Two Jack Main")
    # A backcountry campground's pads are one point in the accommodation layer: no count.
    assert rules.facility_summary({"Facility_Type_Installation": 3000}, {"Camping": 1}) == (
        "Backcountry campground"
    )
    assert rules.facility_name({"Name_e": "Visitor center/Interpretation facility - Parc "
                                "national de la mauricie (Saint-Mathieu)"}) == "Saint-Mathieu"
    assert rules.facility_name({"Name_e": "Winter Warming Hut - Parc national de la Mauricie "
                                "(Lac Étienne)"}) == "Winter Warming Hut (Lac Étienne)"
    assert rules.facility_name({"Name_e": "Information board"}) is None
    assert rules.facility_name({"Name_e": "Egypt Lake Backcountry Shelter (Closed)"}) is None
    assert assembly.osm_hut_summary({"tourism": "wilderness_hut",
                                     "operator": "https://example.com/"}) == "Wilderness hut"


def test_attendance_reads_counts_and_never_a_note_as_zero():
    rows = [["Place", "2025-26 FY Attendance"], ["Banff National Park", "4,558,171"],
            ["Gros Morne National Park", "UR"], ["Wapusk National Park", "81"], []]
    assert rules.attendance(rows) == {"Banff National Park": 4558171, "Wapusk National Park": 81}
    assert "April 2025" in rules.attendance_period()


def test_parks_canadas_own_photographs_are_refused_and_no_others():
    sources = assembly._Sources.__new__(assembly._Sources)
    sources.licences = {
        "a.jpg": {"artist": "Parks Canada / Parcs Canada", "credit": "Own work"},
        "b.jpg": {"artist": "Kdalgleish", "credit": "Own work",
                  "description": "Parks Canada Arctic Circle Sign - Auyuittuq"},
        "c.jpg": {"artist": '<a href="https://flickr.com/x">K. D.</a>',
                  "credit": '<a href="http://www.pc.gc.ca/pn-np/">Long Beach</a>'},
    }
    report = assembly.norway._Report()
    sources.refuse_parks_canada_photos(report)
    assert sources.licences["a.jpg"] is None
    assert sources.licences["b.jpg"] and sources.licences["c.jpg"]


# MARK: - Documents, rail and Wikidata


def test_pdf_links_take_their_heading_where_the_link_says_only_download():
    page = "https://parks.canada.ca/pn-np/ab/banff/visit/brochures"
    html = (
        "<figcaption><strong>Visitor guide </strong><br>"
        '<a href="https://pcweb2.azureedge.net/x/2026_VisitorGuide_BNP_EN.pdf">Download PDF '
        "brochure (2&nbsp;MB)</a></figcaption>"
        '<a href="/x/2026_VisitorGuide_BNP_FR.pdf">Guide (French)</a>'
        '<a href="/x/day-hikes.pdf">Day hikes and rides in the Banff area (1.7 MB)</a>'
    )
    assert fetching.pdf_links(page, html) == [
        {"title": "Visitor guide",
         "url": "https://pcweb2.azureedge.net/x/2026_VisitorGuide_BNP_EN.pdf"},
        {"title": "Day hikes and rides in the Banff area",
         "url": "https://parks.canada.ca/x/day-hikes.pdf"},
    ]
    visit = "https://parks.canada.ca/pn-np/nl/grosmorne/visit"
    links = ('<a href="https://parks.canada.ca/pn-np/nl/grosmorne/visit/cartes-maps">Maps</a>'
             '<a href="https://parks.canada.ca/pn-np/nl/grosmorne/visit/prospectus-brochures">B</a>'
             '<a href="https://parks.canada.ca/pn-np/nl/grosmorne/activ">Things to do</a>')
    assert fetching.document_pages(visit, links) == [
        f"{visit}/cartes-maps", f"{visit}/prospectus-brochures",
    ]
    assert rules.document_kind("Gros Morne map", "x.pdf") == "map"
    assert rules.document_kind("Visitor guide", "x.pdf") == "brochure"


def test_a_route_across_provinces_is_joined_from_each_extracts_part():
    west = {"type": "relation", "id": 1, "tags": {"route": "train", "operator": "VIA Rail"},
            "members": [{"type": "way", "ref": 10, "geometry": [{"lat": 53.0, "lon": -118.0}]},
                        {"type": "way", "ref": 11}]}
    east = {"type": "relation", "id": 1, "tags": {"route": "train", "operator": "VIA Rail"},
            "members": [{"type": "way", "ref": 10},
                        {"type": "way", "ref": 11, "geometry": [{"lat": 52.0, "lon": -106.0}]}]}
    merged = fetching.merge_routes([[west], [east]])
    assert len(merged) == 1
    assert [bool(member.get("geometry")) for member in merged[0]["members"]] == [True, True]
    assert assembly.is_via({"operator": "VIA Rail Canada"})
    assert not assembly.is_via({"operator": "GO Transit"})
    assert fetching.provinces_for(
        __import__("unigrids_pipeline.geo", fromlist=["BoundingBox"]).BoundingBox(
            west=-114.1, south=49.0, east=-113.6, north=49.2)
    ) == ["AB", "BC"]


def test_a_services_two_directions_are_one_line():
    from unigrids_pipeline.countries.no import transport

    west = transport.Route({"id": 1, "tags": {"ref": "1", "from": "Toronto", "to": "Vancouver"},
                            "members": []})
    east = transport.Route({"id": 2, "tags": {"ref": "2", "from": "Vancouver", "to": "Toronto"},
                            "members": []})
    other = transport.Route({"id": 3, "tags": {"ref": "691", "from": "Winnipeg",
                                               "to": "Churchill"}, "members": []})
    assembly.pair_directions([west, east, other])
    assert west.ref == east.ref == "1" and other.ref == "691"


def test_names_match_in_english_and_french_with_their_designation_off():
    assert wiki.normal_name("Wells Gray Provincial Park") == "wells-gray"
    assert wiki.normal_name("Parc national de Frontenac") == "frontenac"
    assert wiki.normal_name("Frontenac National Park (Québec)") == "frontenac"
    assert wiki.normal_name("Parc national du Mont-Tremblant") == "mont-tremblant"
    others = [
        {"qid": "Q1", "coord": (45.5, -71.2), "names": {"frontenac"},
         "article": "https://en.wikipedia.org/wiki/Frontenac_National_Park"},
        {"qid": "Q2", "coord": (51.2, -115.6), "names": {"banff"},
         "article": "https://en.wikipedia.org/wiki/Banff_National_Park"},
    ]
    found = wiki.own_matches(
        [("pp:1", "ppqc", "Frontenac", (45.5, -71.2), 10.0),
         ("pp:2", "pp", "Banff", (51.2, -115.6), 10.0)],
        others,
    )
    # A parc national du Québec takes its "national park" article; Ontario's would not.
    assert set(found) == {"pp:1"}


# MARK: - A build


def _point(x, y, **properties):
    return {"type": "Feature", "geometry": {"type": "Point", "coordinates": [x, y]},
            "properties": properties}


@pytest.fixture
def canada(tmp_path, monkeypatch):
    """A raw store and content folder with one national park, one marine area, two
    provincial parks, Parks Canada facilities and attendance."""
    raw = tmp_path / "raw" / "2026-11-17"

    def write(source, name, payload):
        directory = raw / source
        directory.mkdir(parents=True, exist_ok=True)
        path = directory / name
        if isinstance(payload, str):
            path.write_text(payload)
        else:
            path.write_text(json.dumps(payload))

    write(fetching.CPCAD, "national-parks.geojson", _collection(
        _record(710300000, "Banff National Park Of Canada", "National Park", 1,
                _ring(-116.4, 50.8, 1.2), 664100),
    ))
    write(fetching.CPCAD, "marine-areas.geojson", _collection(
        _record(711900000, "Fathom Five National Marine Park Of Canada", "National Marine Park",
                9, _ring(-81.8, 45.2, 0.2), 11350),
    ))
    write(fetching.CPCAD, "provincial-parks.geojson", _collection(
        _record(480001041, "Peter Lougheed Provincial Park", "Provincial Park", 1,
                _ring(-115.3, 50.5, 0.3), 51448.1, provider=48),
        _record(240000131, "Frontenac National Park (Québec)", "Quebec's national park", 11,
                _ring(-71.2, 45.8, 0.2), 15650, provider=24),
    ))
    write(fetching.FACILITIES, "facilities.geojson", _collection(
        _point(-115.570, 51.178, Name_e="Banff Visitor Centre", Facility_Type_Installation=7002,
               URL_e="https://parks.canada.ca/pn-np/ab/banff/visit"),
        _point(-115.508, 51.230, Name_e="Two Jack Main Campground", Label_e="Two Jack Main",
               Facility_Type_Installation=1001),
        _point(-115.755, 51.359, Name_e="Sawback Lake Backcountry Campground",
               Facility_Type_Installation=3000),
        _point(-115.857, 51.257, Name_e="Moose Meadows Trailhead",
               Facility_Type_Installation=1013),
        _point(-100.0, 49.0, Name_e="Somewhere Else Campground",
               Facility_Type_Installation=1001),
    ))
    write(fetching.FACILITIES, "accommodation.geojson", _collection(
        _point(-115.509, 51.231, Name_e="Two Jack Main", Accommodation_Type=1),
        _point(-115.507, 51.229, Name_e="Two Jack Main", Accommodation_Type=1),
        _point(-115.506, 51.228, Name_e="Two Jack Main", Accommodation_Type=3),
        _point(-115.700, 51.450, Name_e="Bryant Creek Shelter", Accommodation_Type=13),
    ))
    write(fetching.ATTENDANCE, "attendance.csv",
          "Place,2025-26 FY Attendance\r\nBanff National Park,\"4,558,171\"\r\n"
          "Fathom Five National Marine Park,\"256,976\"\r\n")

    content_dir = tmp_path / "content" / "countries" / "ca"
    (content_dir / "guides").mkdir(parents=True)
    (content_dir / "national-parks.json").write_text(json.dumps({"parks": [{
        "id": "ca-np-banff", "name": "Banff", "designation": "National Park",
        "officialName": "Banff National Park",
        "localNames": [{"language": "fr", "text": "Parc national Banff"}],
        "cpcadParentId": 710300000, "passportRegion": "mountainsAndPacific",
        "pcPage": "https://parks.canada.ca/pn-np/ab/banff",
        "attendancePlace": "Banff National Park",
    }]}))
    (content_dir / "guides" / "ca-np-banff.json").write_text(json.dumps({
        "placeID": "ca-np-banff",
        "summary": "Canada's first national park.",
        "facts": {"establishedYear": 1885, "bestSeasons": ["summer"]},
        "sights": [{"name": "Moraine Lake", "note": "Ten peaks.", "location": [51.322, -116.186]},
                   {"name": "Nowhere", "location": [-39.2, 175.6]}],
        "themes": ["theme-mountains"],
    }))
    (tmp_path / "content" / "themes.json").write_text(json.dumps({"themes": [
        {"id": "theme-mountains"},
    ]}))

    monkeypatch.setattr(config, "RAW_DIR", tmp_path / "raw")
    monkeypatch.setattr(config, "CONTENT_DIR", tmp_path / "content")
    monkeypatch.setattr(content, "DIRECTORY", content_dir)
    monkeypatch.setattr(content, "GUIDES_DIR", content_dir / "guides")
    content.parks.cache_clear()
    from unigrids_pipeline.countries.no import content as norway_content

    monkeypatch.setattr(norway_content, "THEMES_PATH", tmp_path / "content" / "themes.json")
    norway_content.theme_ids.cache_clear()
    yield tmp_path
    content.parks.cache_clear()
    norway_content.theme_ids.cache_clear()


def test_a_build_on_the_fixture_gives_records_the_app_decodes(canada):
    images = canada / "images"
    images.mkdir()
    share = assembly.assemble(BuildContext(online=False, images_dir=images))
    places = {place["id"]: place for place in share.places}

    banff = places["ca-np-banff"]
    assert banff["kind"] == "nationalPark" and banff["designation"] == "National Park"
    assert banff["agency"] == "parksCanada" and banff["country"] == "CA"
    assert banff["subdivisions"] == ["CA-AB"] and banff["passportRegion"] == "mountainsAndPacific"
    assert banff["timeZoneID"] == "America/Edmonton"
    assert banff["facts"]["annualVisits"] == 4558171
    assert banff["facts"]["annualVisitsYear"] == 2025
    assert banff["facts"]["establishedYear"] == 1885
    assert banff["officialURL"] == "https://parks.canada.ca/pn-np/ab/banff"
    assert banff["localNames"] == [{"language": "fr", "text": "Parc national Banff"}]

    fathom = places["ca-mca-fathom-five"]
    assert fathom["kind"] == "marineConservationArea" and fathom["agency"] == "parksCanada"
    assert fathom["designation"] == "National Marine Park"
    assert fathom["passportRegion"] == "ontario" and fathom["timeZoneID"] == "America/Toronto"
    assert fathom["facts"] == {
        "areaHectares": 11350, "annualVisits": 256976, "annualVisitsYear": 2025,
        "annualVisitsPeriod": rules.attendance_period(),
    }
    lougheed = places["ca-pp-peter-lougheed"]
    assert lougheed["kind"] == "provincialPark" and lougheed["agency"] == "provincialAgency"
    assert lougheed["designation"] == "Provincial Park" and lougheed["subdivisions"] == ["CA-AB"]
    frontenac = places["ca-pp-frontenac"]
    assert frontenac["designation"] == "Provincial Park"
    assert frontenac["passportRegion"] == "quebec"
    assert frontenac["localNames"][0]["language"] == "fr"
    assert set(places) == set(share.boundaries)

    pois = {poi["name"]: poi for poi in share.pois}
    assert pois["Moraine Lake"]["rank"] == 1
    assert pois["Moraine Lake"]["id"] == "poi-ca-banff-moraine-lake"
    assert "Nowhere" not in pois and "Somewhere Else Campground" not in pois
    assert pois["Banff Visitor Centre"]["kind"] == "visitorCentre"
    two_jack = pois["Two Jack Main Campground"]
    assert two_jack["kind"] == "campground"
    assert two_jack["summary"] == "Front-country campground · 2 sites · 1 oTENTik"
    assert pois["Sawback Lake Backcountry Campground"]["summary"] == "Backcountry campground"
    assert pois["Bryant Creek Shelter"]["kind"] == "hut"
    # Trailheads anchor the trails' walking order and are not shipped as pins.
    assert "Moose Meadows Trailhead" not in pois

    for place in share.places:
        assert place["country"] == "CA"
        assert place["passportRegion"] in rules.PASSPORT_REGIONS
        assert place["timeZoneID"] in rules.CANADIAN_ZONES
        assert place["subdivisions"] and all(s.startswith("CA-") for s in place["subdivisions"])
        assert "states" not in place
    assert share.expects_summary == {"ca-np-banff"}
    assert {registry.path.name for registry in share.registries} == {
        "places.json", "pois.json", "trails.json",
    }
    # No raw trails or elevation tiles in the fixture, and offline: none invented.
    assert share.trails == [] and "highestElevationMetres" not in banff["facts"]
    assert share.registries[0].owner("ca-pp-peter-lougheed") == "cpcad:480001041"


# MARK: - The package


def test_canada_keeps_the_country_contract():
    canada = countries.load("ca")
    assert canada.CODE == "ca" and canada.NAME == "Canada"
    assert "ca" in countries.KNOWN and countries.DEFAULT == ("us",)
    places = [{"kind": "nationalPark", "summary": "…"}, {"kind": "provincialPark"},
              {"kind": "marineConservationArea"}]
    note = canada.manifest_note(places)
    assert note.startswith("Canada: all 1 national parks")
    assert "not affiliated with Parks Canada" in note and "beaver" in note


def test_canada_is_registered_abroad():
    assert "ca" in abroad_outlines.COUNTRIES and "ca" in abroad_trails.COUNTRIES
    assert abroad_trails.OSM_TRAIL_SOURCES["ca"] == "ca-osm-trails"
    assert abroad_packs.COUNTRY_NAMES["ca"] == "Canada"
    assert "beaver" in abroad_packs.NOT_AFFILIATED["ca"]
    assert "wordmark" in abroad_packs.NOT_AFFILIATED["ca"]
    assert abroad_outlines.COUNTRY_SOURCES["ca"] == ("ca-cpcad", "national-parks.geojson")
    assert {park["id"] for park in abroad_outlines.park_list("ca")} == {
        park["id"] for park in content.parks()
    }
    alberta = osm_pbf.extract_for("ca-ab")
    assert alberta.url.endswith("/north-america/canada/alberta-latest.osm.pbf")
    assert alberta.source == "geofabrik-ca-ab"
    assert len({osm_pbf.extract_for(f"ca-{code.lower()}").source
                for code in osm_pbf.CANADA_PROVINCES}) == 13
