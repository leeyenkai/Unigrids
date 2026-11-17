"""Australia's rules and records, on small fixtures and no network.

The rules are the ones a wrong answer would ship quietly: which state, passport book and
zone a place belongs to, which CAPAD records make a park, which date and area CAPAD's
fields give, how Queensland's track classes read, which OpenStreetMap elements are a
visitor's facilities, and that every identifier goes through a registry keyed on its
source's own id — with no US fallback anywhere.
"""

from __future__ import annotations

import datetime as dt
import json

import pytest

from unigrids_pipeline import config, countries, ids
from unigrids_pipeline.countries import BuildContext
from unigrids_pipeline.countries.abroad import outlines as abroad_outlines
from unigrids_pipeline.countries.abroad import packs as abroad_packs
from unigrids_pipeline.countries.abroad import trails as abroad_trails
from unigrids_pipeline.countries.au import (
    assembly,
    content,
    fetching,
    qldtracks,
    rules,
    wiki,
)
from unigrids_pipeline.sources import osm_pbf

# MARK: - The park list


def test_the_park_list_holds_the_fifty_one_parks():
    parks = content.parks()
    assert len(parks) == 51
    assert len({park["id"] for park in parks}) == 51
    assert all(park["id"].startswith("au-np-") for park in parks)
    assert all(park["name"].endswith(("National Park", ")")) for park in parks)
    commonwealth = {park["id"] for park in parks if park["agency"] == rules.PARKS_AUSTRALIA}
    assert commonwealth == {
        "au-np-kakadu", "au-np-uluru-kata-tjuta", "au-np-booderee", "au-np-christmas-island",
        "au-np-pulu-keeling", "au-np-norfolk-island",
    }


def test_every_park_is_in_its_states_passport_book():
    regions: dict[str, int] = {}
    for park in content.parks():
        state = park["state"].removeprefix("AU-")
        assert state in rules.NAMES
        assert park["passportRegion"] == rules.passport_region(state)
        regions[park["passportRegion"]] = regions.get(park["passportRegion"], 0) + 1
    assert set(regions) == rules.PASSPORT_REGIONS
    assert regions == {
        "newSouthWales": 14, "victoria": 4, "queensland": 9, "southAustralia": 2,
        "westernAustralia": 6, "tasmania": 9, "northernTerritory": 4,
        "externalTerritories": 3,
    }


def test_every_park_has_an_agency_page_among_its_sources():
    for park in content.parks():
        assert rules.official_page((content.guide(park["id"]) or {}).get("sources")), park["id"]


def test_australian_identifiers_carry_the_country():
    assert ids.country_place_id("au", "snp", "Tjoritja / West MacDonnell") == (
        "au-snp-tjoritja-west-macdonnell"
    )
    assert ids.country_place_id("au", "np", "Uluṟu-Kata Tjuṯa") == "au-np-uluru-kata-tjuta"
    assert ids.country_of("au-snp-wollemi") == "au"
    assert ids.country_of("poi-au-kakadu-ubirr") == "au"
    with pytest.raises(ValueError):
        ids.country_place_id("au", "pp", "Somewhere")


def test_a_state_national_park_is_pinned_to_its_capad_name(tmp_path):
    registry = ids.Registry(tmp_path / "places.json")
    first = registry.resolve("capad:VIC/Mitchell River", "au-snp-mitchell-river",
                             qualifier="vic")
    second = registry.resolve("capad:QLD/Mitchell River", "au-snp-mitchell-river",
                              qualifier="qld")
    assert (first, second) == ("au-snp-mitchell-river", "au-snp-mitchell-river-qld")


# MARK: - Where a place is


@pytest.mark.parametrize(
    ("code", "point", "state"),
    [("1", None, "NSW"), ("8", None, "ACT"), ("7", None, "NT"),
     ("9", (-35.15, 150.70), "JBT"), ("9", (-10.49, 105.62), "CX"),
     ("9", (-12.17, 96.84), "CC"), ("9", (-11.83, 96.82), "CC"),
     ("9", (-29.04, 167.95), "NF"), ("9", (-33.0, 151.0), None), ("Z", None, None)],
)
def test_the_abs_states_and_the_other_territories(code, point, state):
    latitude, longitude = point or (None, None)
    assert rules.abs_state(code, latitude, longitude) == state


def test_capads_states_and_its_external_territories():
    assert rules.capad_state("NSW") == "NSW" and rules.capad_state("JBT") == "JBT"
    assert rules.capad_state("EXT", -29.03, 167.94) == "NF"
    assert rules.capad_state("EXT") is None and rules.capad_state("NZ") is None
    assert rules.capad_state_of("AU-CX") == "EXT" and rules.capad_state_of("AU-JBT") == "JBT"


def test_a_place_keeps_its_own_australian_zone_and_only_that():
    assert rules.time_zone("Australia/Broken_Hill", ["NSW"]) == "Australia/Broken_Hill"
    assert rules.time_zone("Australia/Lindeman", ["QLD"]) == "Australia/Lindeman"
    assert rules.time_zone("Australia/Eucla", ["WA"]) == "Australia/Eucla"
    assert rules.time_zone("Australia/Canberra", ["ACT"]) == "Australia/Sydney"
    # A centre at sea, or a zone that is not Australian, takes its state's.
    assert rules.time_zone("Etc/GMT-10", ["QLD"]) == "Australia/Brisbane"
    assert rules.time_zone(None, ["TAS"]) == "Australia/Hobart"
    assert rules.time_zone("Australia/Sydney", ["NF"]) == "Pacific/Norfolk"
    assert rules.time_zone(None, ["CX"]) == "Indian/Christmas"
    assert rules.time_zone(None, []) is None


# MARK: - CAPAD


def _gazetted(year, month, day):
    """A date as CAPAD returns it: midnight in Canberra, 14:00 UTC the day before."""
    moment = dt.datetime(year, month, day, tzinfo=dt.UTC) - dt.timedelta(hours=10)
    return int(moment.timestamp() * 1000)


@pytest.mark.parametrize(
    ("records", "expected"),
    [
        # Northern Territory: the whole park's area on each parcel.
        ([{"GAZ_AREA": 146118.0, "GIS_AREA": 100000.0},
          {"GAZ_AREA": 146118.0, "GIS_AREA": 45845.0}], (146118.0, "gazetted")),
        # Tasmania records none: the mapped boundary's area.
        ([{"GAZ_AREA": 0.0, "GIS_AREA": 51807.2}], (51807.2, "mapped")),
        # South Australia's gazetted area that does not describe the parcel.
        ([{"GAZ_AREA": 5941.0, "GIS_AREA": 658.0}], (658.0, "mapped")),
        ([{"GAZ_AREA": 4117.0, "GIS_AREA": 4248.0}], (4117.0, "gazetted")),
        ([{"GAZ_AREA": None, "GIS_AREA": None}], (None, None)),
    ],
)
def test_a_parks_area_is_gazetted_where_it_agrees_with_the_map(records, expected):
    assert rules.area_hectares(records) == expected


@pytest.mark.parametrize(
    ("capad", "shown"),
    [("Wollemi", "Wollemi"), ("Cudmore (Limited Depth)", "Cudmore"),
     ("Bandilngan  (Windjana Gorge)", "Bandilngan (Windjana Gorge)"),
     ("Unnamed WA17519", None), ("", None)],
)
def test_a_capad_name_is_shown_as_the_park_is_called(capad, shown):
    assert rules.display_name(capad) == shown


@pytest.mark.parametrize(
    ("name", "split"),
    [("Kakadu National Park", ("Kakadu", "National Park")),
     ("Daintree National Park (CYPAL)", ("Daintree", "National Park (CYPAL)")),
     ("Boodjamulla National Park (Aboriginal Land)",
      ("Boodjamulla", "National Park (Aboriginal Land)")),
     ("Grampians (Gariwerd) National Park", ("Grampians (Gariwerd)", "National Park"))],
)
def test_an_agencys_name_splits_into_name_and_designation(name, split):
    assert assembly.split_name(name) == split


def test_agencies_read_as_the_apps():
    assert rules.agency("Parks Australia") == "parksAustralia"
    assert rules.agency("NSW National Parks and Wildlife Service") == "stateAgency"
    assert rules.AUTHORITIES["NRE_TAS"] == "Parks and Wildlife Service Tasmania"


def _ring(x, y, size):
    return [[x, y], [x + size, y], [x + size, y + size], [x, y + size], [x, y]]


def _record(object_id, name, kind, state, ring, *, gaz_area=0.0, gis_area=1000.0,
            date=None, authority="NSW_DCCEEW"):
    return {
        "type": "Feature",
        "geometry": {"type": "Polygon", "coordinates": [ring]},
        "properties": {
            "OBJECTID": object_id, "NAME": name, "TYPE": kind, "STATE": state,
            "GAZ_AREA": gaz_area, "GIS_AREA": gis_area, "GAZ_DATE": date,
            "AUTHORITY": authority,
        },
    }


def _collection(*features):
    return {"type": "FeatureCollection", "features": list(features)}


def test_a_park_is_every_record_of_its_names_in_its_state(tmp_path):
    (tmp_path / "national-parks.geojson").write_text(json.dumps(_collection(
        _record(1, "Daintree", "National Park", "QLD", _ring(145.3, -16.3, 0.2)),
        _record(2, "Daintree", "National Park Aboriginal", "QLD", _ring(145.2, -16.0, 0.2)),
        _record(3, "Boodjamulla (Lawn Hill)", "National Park", "QLD", _ring(138.4, -18.7, 0.2)),
        _record(4, "Norfolk Island (Phillip Island)", "National Park (Commonwealth)", "EXT",
                _ring(167.94, -29.12, 0.02)),
    )))
    (tmp_path / "state-national-parks.geojson").write_text(json.dumps(_collection(
        _record(1, "Daintree", "National Park", "QLD", _ring(145.3, -16.3, 0.2)),
        _record(5, "Mitchell River", "National Park", "VIC", _ring(147.4, -37.6, 0.1)),
        _record(6, "Mitchell River", "National Park", "QLD", _ring(142.0, -15.5, 0.5)),
        _record(7, "Royal", "National Park", "NSW", _ring(151.0, -34.1, 0.1)),
        _record(8, "Royal", "Nature Reserve", "NSW", _ring(151.2, -34.1, 0.1)),
    )))
    areas = fetching.read_areas(tmp_path)
    daintree = areas["np:au-np-daintree"]
    # Both of Daintree's types; the record both queries returned only once.
    assert len(daintree.parts) == 2 and len(daintree.polygons) == 2
    assert len(areas["np:au-np-boodjamulla"].parts) == 1
    assert areas["np:au-np-norfolk-island"].state == "EXT"
    assert len(areas["np:au-np-royal"].parts) == 1  # the namesake reserve is not the park
    assert [area.key for area in fetching.second_tier(areas)] == [
        "QLD/Mitchell River", "VIC/Mitchell River",
    ]


def test_outlines_for_packs_join_a_parks_records_by_name_and_state():
    features = [
        _record(1, "Kakadu", "National Park (Commonwealth)", "NT", _ring(132.4, -13.0, 0.5)),
        _record(2, "Norfolk Island (Mt Pitt)", "National Park (Commonwealth)", "EXT",
                _ring(167.94, -29.02, 0.02)),
        _record(3, "Norfolk Island (Phillip Island)", "National Park (Commonwealth)", "EXT",
                _ring(167.94, -29.12, 0.02)),
        _record(4, "Kakadu", "National Park", "QLD", _ring(145.0, -17.0, 0.1)),
    ]
    found = abroad_outlines.capad_park_polygons(features, content.parks())
    assert set(found) == {"au-np-kakadu", "au-np-norfolk-island"}
    assert len(found["au-np-kakadu"]) == 1 and len(found["au-np-norfolk-island"]) == 2


# MARK: - Queensland's tracks


@pytest.mark.parametrize(
    ("published", "grade", "band"),
    [("Track class 1 to AS 2156.1", "1", "easy"), ("Track class 2 to AS 2156.1", "2", "easy"),
     ("Track class 3 to AS 2156.1", "3", "moderate"),
     ("Track class 4 to AS 2156.1", "4", "strenuous"),
     ("Track class 5 to AS 2156.1", "5", "veryStrenuous"),
     ("Unclassified", None, None), (None, None, None)],
)
def test_queenslands_track_classes_read_into_the_bands(published, grade, band):
    assert rules.track_grade(published) == grade
    assert rules.band(grade) == band


@pytest.mark.parametrize(
    ("published", "name"),
    [("BB - Caves circuit", "Caves circuit"), ("BB- Illinbah Circuit", "Illinbah Circuit"),
     ("BB Border Track (Great Walk)", "Border Track (Great Walk)"),
     ("GM - Box Forest Circuit", "Box Forest Circuit"),
     ("GC Hinterland Great Walk - Springbrook", "GC Hinterland Great Walk - Springbrook"),
     ("  Coomera\xa0Track ", "Coomera Track")],
)
def test_a_track_is_named_without_lamingtons_section_codes(published, name):
    assert rules.track_name(published) == name


def test_a_track_class_is_a_published_grade():
    assert rules.published_grade("4") == {
        "system": "australianWalkingTrackGrade", "grade": "4",
        "publisher": "Queensland Parks and Wildlife Service",
        "sourceURL": rules.QPWS_TRACKS_URL,
    }


def _track(object_id, name, line, *, ped="Track class 3 to AS 2156.1", status="Open",
           kind="Walking Track", mtb="Unclassified"):
    return {
        "type": "Feature",
        "geometry": {"type": "LineString", "coordinates": line},
        "properties": {"objectid": object_id, "name": name, "ped": ped, "status": status,
                       "class": kind, "mtb": mtb},
    }


@pytest.fixture
def track_features():
    border = [[153.10, -28.23], [153.11, -28.22], [153.12, -28.21]]
    border_on = [[153.12, -28.21], [153.13, -28.20]]
    return [
        _track(1, "Border Track", border, ped="Track class 4 to AS 2156.1",
               kind="minimally formed natural"),
        _track(2, "Border Track", border_on, ped="Unclassified", kind="Pedestrian Bridge"),
        _track(3, "Box Forest", [[153.15, -28.25], [153.16, -28.26]]),
        _track(4, "Box Forest", [[153.16, -28.26], [153.17, -28.27]],
               ped="Track class 4 to AS 2156.1"),
        _track(5, "Old Road", [[153.2, -28.3], [153.21, -28.31]], status="Closed"),
        _track(6, "Fire Trail", [[153.2, -28.2], [153.21, -28.21]], ped="Unclassified",
               kind="formed natural"),
        _track(7, None, [[153.1, -28.3], [153.11, -28.31]]),
        _track(8, "Far Away", [[145.0, -17.0], [145.01, -17.01]]),
    ]


def _lamington():
    return [[[(153.0, -28.4), (153.3, -28.4), (153.3, -28.1), (153.0, -28.1)]]]


def test_open_named_tracks_join_by_name_with_the_class_they_agree_on(track_features):
    park = {"id": "au-np-lamington", "state": "AU-QLD"}
    found = qldtracks.routes(park, track_features, _lamington())
    assert [(route.name, len(route.segments)) for route in found] == [
        ("Border Track", 2), ("Box Forest", 2),
    ]
    border, box = found
    assert border.key == "qpws:lamington/border-track" and border.source == "qpws"
    # A bridge QPWS leaves unclassified does not unsay the track's class.
    assert border.extra[qldtracks.GRADE_KEY]["grade"] == "4"
    # Records of one track that disagree leave its grade unsaid.
    assert qldtracks.GRADE_KEY not in box.extra


def test_a_park_outside_queensland_takes_no_queensland_tracks(track_features):
    park = {"id": "au-np-kosciuszko", "state": "AU-NSW"}
    assert qldtracks.routes(park, track_features, _lamington()) == []
    assert abroad_trails.is_thin("au", [])


def test_a_queensland_track_is_measured_into_a_record_with_its_grade(track_features, tmp_path):
    park = {"id": "au-np-lamington", "state": "AU-QLD"}
    route = qldtracks.routes(park, track_features, _lamington())[0]
    registry = ids.Registry(tmp_path / "trails.json")
    record = abroad_trails.trail_record("au", park, route, lambda lon, lat: None, [], [],
                                        registry)
    assert record is not None
    assert record["id"] == "trail-au-lamington-border-track"
    assert record["source"] == "qpws" and record["uses"] == "Hike"
    assert record["publishedGrade"]["system"] == "australianWalkingTrackGrade"
    assert registry.owner(record["id"]) == "qpws:lamington/border-track"


# MARK: - Facilities


@pytest.mark.parametrize(
    ("tags", "kind"),
    [({"tourism": "wilderness_hut", "name": "Seamans Hut"}, "hut"),
     ({"tourism": "alpine_hut"}, "hut"),
     ({"tourism": "camp_site", "name": "Tidal River"}, "campground"),
     ({"tourism": "information", "information": "office"}, "visitorCentre"),
     ({"tourism": "information", "information": "board"}, None),
     ({"amenity": "shelter"}, None)],
)
def test_openstreetmap_elements_read_as_a_visitors_facilities(tags, kind):
    assert rules.facility_kind(tags) == kind
    assert osm_pbf.is_facility(tags) == (kind is not None)


def test_a_private_or_closed_facility_is_not_a_visitors():
    assert rules.is_public({"name": "Waterfall Hut"})
    assert not rules.is_public({"name": "Waterfall Hut", "access": "private"})
    assert not rules.is_public({"name": "Old Hut (closed)"})
    assert not rules.is_public({"name": "Rangers Hut"})
    assert rules.facility_summary({"tourism": "camp_site", "operator": "NPWS", "fee": "yes"}) == (
        "Campground · NPWS · fee"
    )


@pytest.mark.parametrize(
    ("name", "kept"),
    [("Bowali Visitor Centre", True), ("Mungo Visitor Centre", True),
     ("Halls Gap Information Centre", True), ("Tour Desk", False), ("Information", False),
     ("Hinze Dam Information Centre", False), ("Colobra Tree", False),
     ("Tidbinbilla Nature Reserve Visitor Centre", False),
     ("Twelve Apostles Visitor Centre Kiosk", False)],
)
def test_an_information_office_is_a_visitor_centre_by_its_name(name, kept):
    assert rules.is_visitor_centre_name(name) == kept


# MARK: - Rail


@pytest.mark.parametrize(
    ("tags", "kept"),
    [({"network": "NSW TrainLink", "operator": "NSW TrainLink"}, True),
     ({"network": "PTV - Metropolitan Trains"}, True),
     ({"name": "The Ghan", "service": "tourism"}, True),
     ({"operator": "Transwa", "name": "Australind Train"}, True),
     ({"name": "Cathkin-Alexandra", "network": "vicrail", "railway": "abandoned"}, False),
     ({"name": "Bellarine Heritage Railway"}, False),
     ({"name": "Hobart - Boyer (Freight)", "operator": "TasRail", "service": "industrial"},
      False),
     ({"name": "Melbourne Metro 2", "network": "Melbourne Metropolitan Trains"}, False)],
)
def test_rail_is_the_trains_a_visitor_can_take(tags, kept):
    assert rules.is_passenger_service(tags) == kept


def test_a_routes_tags_name_the_line_it_is_one_service_of():
    assert rules.line_tags({"ref": "CBE=>WFY"})["ref"] == "CBE"
    assert rules.line_tags({"ref": "T4"})["ref"] == "T4"
    spirit = rules.line_tags({"ref": "Spirit of Queensland", "name": "Spirit of Queensland: "
                              "Brisbane–Cairns"})
    assert "ref" not in spirit and spirit["name"] == "Spirit of Queensland"
    perth = rules.line_tags({"name": "Airport Line: Perth–High Wycombe"})
    assert perth["name"] == "Airport Line"
    ends = rules.line_tags({"ref": "34", "from": "Casino Station, Platform 1",
                            "to": "Central Station, Platform 3"})
    assert (ends["from"], ends["to"]) == ("Casino", "Central")


def test_the_australian_extract_is_registered():
    extract = osm_pbf.extract_for("au")
    assert extract.url.endswith("/australia-oceania/australia-latest.osm.pbf")
    assert extract.source == "geofabrik-au"


# MARK: - Documents


def test_a_parks_documents_are_its_own():
    assert rules.document_title("Ikara-Flinders Ranges Nation\xadal Park map") == (
        "Ikara-Flinders Ranges National Park map"
    )
    assert not rules.is_the_parks_document("Public Interest Disclosure Policy")
    assert rules.is_the_parks_document("Grampians National Park Visitor Guide")
    assert rules.document_kind("Wilsons Promontory National Park map overview", "x.pdf") == "map"
    assert rules.document_kind("Budj Bim National Park Visitor Guide", "x.pdf") == "brochure"


def test_agency_pages_and_their_pdfs():
    page = "https://www.parks.vic.gov.au/places-to-see/parks/grampians-national-park"
    html = (
        '<a href="/-/media/guide.pdf?rev=1">Grampians National Park Visitor Guide '
        '(PDF 2.1 MB)</a><a href="/-/media/guide.pdf?rev=1">again</a>'
    )
    assert fetching.pdf_links(page, html) == [{
        "title": "Grampians National Park Visitor Guide",
        "url": "https://www.parks.vic.gov.au/-/media/guide.pdf?rev=1",
    }]
    assert rules.official_page([
        {"url": "https://en.wikipedia.org/wiki/Kakadu_National_Park"},
        {"url": "https://parksaustralia.gov.au/kakadu/"},
    ]) == "https://parksaustralia.gov.au/kakadu/"


# MARK: - Wikidata


def test_names_match_with_their_designation_off():
    assert wiki.normal_name("Wollemi National Park") == "wollemi"
    assert wiki.normal_name("Daintree National Park (CYPAL)") == "daintree"
    assert wiki.normal_name("Mitchell River National Park, Victoria") == "mitchell-river"
    others = [
        {"qid": "Q1", "coord": (-33.0, 150.6), "names": {"wollemi"},
         "article": "https://en.wikipedia.org/wiki/Wollemi_National_Park"},
        {"qid": "Q2", "coord": (-35.6, 138.6), "names": {"deep-creek"},
         "article": "https://en.wikipedia.org/wiki/Deep_Creek_Conservation_Park"},
    ]
    found = wiki.own_matches(
        [("snp:NSW/Wollemi", "snp", "Wollemi", (-33.0, 150.6), 10.0),
         ("snp:SA/Deep Creek", "snp", "Deep Creek", (-35.6, 138.6), 10.0)],
        others,
    )
    # A conservation park of the same name is not the national park.
    assert set(found) == {"snp:NSW/Wollemi"}


# MARK: - A build


@pytest.fixture
def australia(tmp_path, monkeypatch):
    """A raw store and content folder with one national park, two state national parks,
    the states, and OpenStreetMap's facilities."""
    raw = tmp_path / "raw" / "2026-11-17"

    def write(source, name, payload):
        directory = raw / source
        directory.mkdir(parents=True, exist_ok=True)
        (directory / name).write_text(json.dumps(payload))

    gazetted = _gazetted

    write(fetching.CAPAD, "national-parks.geojson", _collection(
        _record(1, "Kosciuszko", "National Park", "NSW", _ring(148.2, -36.6, 0.4),
                gaz_area=673790, gis_area=688945, date=gazetted(1967, 10, 1)),
    ))
    write(fetching.CAPAD, "state-national-parks.geojson", _collection(
        _record(2, "Brindabella", "National Park", "NSW", _ring(148.8, -35.4, 0.1),
                gaz_area=18472, gis_area=18500, date=gazetted(1986, 11, 14)),
        _record(3, "Ben Lomond", "National Park", "TAS", _ring(147.6, -41.6, 0.1),
                gaz_area=0, gis_area=18145.4, date=gazetted(1947, 5, 1),
                authority="NRE_TAS"),
        _record(4, "Unnamed WA17519", "National Park", "WA", _ring(116.0, -31.0, 0.1),
                authority="WA_DBCA"),
    ))
    write(fetching.STATES, "states.geojson", _collection(
        {"type": "Feature", "properties": {"state_code_2021": "1"},
         "geometry": {"type": "Polygon", "coordinates": [_ring(141.0, -37.5, 12.0)]}},
        {"type": "Feature", "properties": {"state_code_2021": "6"},
         "geometry": {"type": "Polygon", "coordinates": [_ring(144.5, -43.7, 4.0)]}},
    ))
    write(fetching.OSM, fetching.FACILITIES_FILE, {"elements": [
        {"type": "node", "id": 11, "lat": -36.45, "lon": 148.28,
         "tags": {"tourism": "wilderness_hut", "name": "Seamans Hut"}},
        {"type": "way", "id": 12, "center": {"lat": -36.40, "lon": 148.40},
         "tags": {"tourism": "camp_site", "name": "Island Bend Campground", "fee": "no"}},
        {"type": "node", "id": 13, "lat": -36.416, "lon": 148.622,
         "tags": {"tourism": "information", "information": "office",
                  "name": "Snowy Region Visitor Centre"}},
        {"type": "node", "id": 14, "lat": -36.30, "lon": 148.30,
         "tags": {"tourism": "camp_site"}},
        {"type": "node", "id": 15, "lat": -30.0, "lon": 150.0,
         "tags": {"tourism": "camp_site", "name": "Far Away Campground"}},
    ]})

    content_dir = tmp_path / "content" / "countries" / "au"
    (content_dir / "guides").mkdir(parents=True)
    (content_dir / "national-parks.json").write_text(json.dumps({"parks": [{
        "id": "au-np-kosciuszko", "name": "Kosciuszko National Park", "state": "AU-NSW",
        "agency": "NSW National Parks and Wildlife Service", "capadName": "Kosciuszko",
        "passportRegion": "newSouthWales",
    }]}))
    (content_dir / "guides" / "au-np-kosciuszko.json").write_text(json.dumps({
        "placeID": "au-np-kosciuszko",
        "summary": "The roof of the continent.",
        "facts": {"bestSeasons": ["summer"]},
        "sights": [
            {"name": "Mount Kosciuszko", "note": "2,228 metres.",
             "location": [-36.45583, 148.26361]},
            {"name": "Snowy Region Visitor Centre", "kind": "visitorCentre",
             "location": [-36.41491, 148.62169]},
            {"name": "Nowhere", "location": [51.3, -116.2]},
        ],
        "sources": [{"title": "Kosciuszko National Park — NPWS",
                     "url": "https://www.nationalparks.nsw.gov.au/visit-a-park/parks/"
                            "kosciuszko-national-park"}],
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


def test_a_build_on_the_fixture_gives_records_the_app_decodes(australia):
    images = australia / "images"
    images.mkdir()
    share = assembly.assemble(BuildContext(online=False, images_dir=images))
    places = {place["id"]: place for place in share.places}

    park = places["au-np-kosciuszko"]
    assert park["name"] == "Kosciuszko" and park["designation"] == "National Park"
    assert park["kind"] == "nationalPark" and park["agency"] == "stateAgency"
    assert park["managedBy"] == "NSW National Parks and Wildlife Service"
    assert park["country"] == "AU" and park["subdivisions"] == ["AU-NSW"]
    assert park["passportRegion"] == "newSouthWales"
    assert park["timeZoneID"] == "Australia/Sydney"
    assert park["officialURL"].startswith("https://www.nationalparks.nsw.gov.au/")
    # The guide gives no year and CAPAD's is the 1967 Act's: none, rather than a wrong one.
    assert "establishedYear" not in park["facts"]
    assert "annualVisits" not in park["facts"]

    brindabella = places["au-snp-brindabella"]
    assert brindabella["kind"] == "stateNationalPark" and brindabella["agency"] == "stateAgency"
    assert brindabella["designation"] == "National Park"
    assert brindabella["managedBy"] == "NSW National Parks and Wildlife Service"
    assert brindabella["facts"] == {"areaHectares": 18472}
    ben_lomond = places["au-snp-ben-lomond"]
    assert ben_lomond["subdivisions"] == ["AU-TAS"] and ben_lomond["passportRegion"] == "tasmania"
    assert ben_lomond["timeZoneID"] == "Australia/Hobart"
    assert ben_lomond["facts"] == {"areaHectares": 18145}
    assert not any(place_id.startswith("au-snp-unnamed") for place_id in places)
    assert set(places) == set(share.boundaries)

    pois = {poi["name"]: poi for poi in share.pois}
    assert pois["Mount Kosciuszko"]["rank"] == 1
    assert pois["Mount Kosciuszko"]["id"] == "poi-au-kosciuszko-mount-kosciuszko"
    assert "Nowhere" not in pois and "Far Away Campground" not in pois
    assert pois["Seamans Hut"]["kind"] == "hut"
    assert pois["Seamans Hut"]["id"] == "poi-au-kosciuszko-seamans-hut"
    assert pois["Island Bend Campground"]["summary"] == "Campground · no fee"
    # The visitor centre the guide lists is the guide's, once.
    assert [poi["kind"] for poi in share.pois].count("visitorCentre") == 1

    for place in share.places:
        assert place["country"] == "AU"
        assert place["passportRegion"] in rules.PASSPORT_REGIONS
        assert place["timeZoneID"] in rules.AUSTRALIAN_ZONES
        assert place["subdivisions"] and all(s.startswith("AU-") for s in place["subdivisions"])
        assert place["agency"] in ("parksAustralia", "stateAgency")
        assert "states" not in place
    assert share.expects_summary == {"au-np-kosciuszko"}
    assert {registry.path.name for registry in share.registries} == {
        "places.json", "pois.json", "trails.json",
    }
    # No raw trails or elevation tiles in the fixture, and offline: none invented.
    assert share.trails == [] and "highestElevationMetres" not in park["facts"]
    assert share.registries[0].owner("au-snp-brindabella") == "capad:NSW/Brindabella"


# MARK: - The package


def test_australia_keeps_the_country_contract():
    australia = countries.load("au")
    assert australia.CODE == "au" and australia.NAME == "Australia"
    assert "au" in countries.KNOWN and countries.DEFAULT == ("us",)
    places = [{"kind": "nationalPark", "summary": "…"}, {"kind": "stateNationalPark"}]
    note = australia.manifest_note(places)
    assert note.startswith("Australia: 1 national parks with a guide")
    assert "not affiliated with Parks Australia" in note and "logos" in note


def test_australia_is_registered_abroad():
    assert "au" in abroad_outlines.COUNTRIES and "au" in abroad_trails.COUNTRIES
    assert abroad_trails.OSM_TRAIL_SOURCES["au"] == "au-osm-trails"
    assert "au" in abroad_trails.AGENCY_TRAILS
    assert abroad_packs.COUNTRY_NAMES["au"] == "Australia"
    assert "Parks Australia" in abroad_packs.NOT_AFFILIATED["au"]
    assert "logos" in abroad_packs.NOT_AFFILIATED["au"]
    assert abroad_outlines.COUNTRY_SOURCES["au"] == ("au-capad", "national-parks.geojson")
    assert {park["id"] for park in abroad_outlines.park_list("au")} == {
        park["id"] for park in content.parks()
    }
    assert abroad_packs.is_abroad("au-np-kakadu")
