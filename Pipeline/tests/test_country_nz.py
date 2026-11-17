"""New Zealand's rules and records, on small fixtures and no network.

The rules are the ones a wrong answer would ship quietly: which region and passport book a
place belongs to, which Public Conservation Land records are parks and what they are
called, how DOC's track categories read, and that every identifier goes through a
registry keyed on its source's own id — with no US fallback anywhere.
"""

from __future__ import annotations

import json

import pytest

from unigrids_pipeline import config, countries, ids
from unigrids_pipeline.countries import BuildContext
from unigrids_pipeline.countries.abroad import outlines as abroad_outlines
from unigrids_pipeline.countries.abroad import packs as abroad_packs
from unigrids_pipeline.countries.abroad import trails as abroad_trails
from unigrids_pipeline.countries.nz import assembly, content, fetching, rules, tracks, wiki
from unigrids_pipeline.sources import osm_pbf

# MARK: - The park list


def test_the_park_list_holds_the_thirteen_national_parks():
    parks = content.parks()
    assert len(parks) == 13
    assert len({park["name"] for park in parks}) == 13
    assert len({park["napalisId"] for park in parks}) == 13
    assert all(park["id"].startswith("nz-np-") for park in parks)
    assert all(park["docPage"].startswith("https://www.doc.govt.nz/") for park in parks)


def test_every_national_park_is_in_its_passport_book():
    regions = {park["id"]: park["passportRegion"] for park in content.parks()}
    assert {park for park, region in regions.items() if region == "northIsland"} == {
        "nz-np-tongariro", "nz-np-te-papa-kura-o-taranaki", "nz-np-whanganui",
    }
    assert {park for park, region in regions.items() if region == "lowerSouthIsland"} == {
        "nz-np-mount-aspiring", "nz-np-fiordland", "nz-np-rakiura",
    }
    assert sum(1 for region in regions.values() if region == "upperSouthIsland") == 7


def test_park_identifiers_are_their_names_slugged():
    for park in content.parks():
        assert park["id"] == ids.country_place_id("nz", "np", park["id"].removeprefix("nz-np-"))
    assert content.park_slug("nz-np-aoraki-mount-cook") == "aoraki-mount-cook"
    rakiura = next(park for park in content.parks() if park["id"] == "nz-np-rakiura")
    assert "Bluff" in rakiura["reachedBy"]
    local = [park for park in content.parks() if park.get("localNames")]
    assert all(name["language"] == "mi" for park in local for name in park["localNames"])


# MARK: - Identifiers


def test_new_zealand_identifiers_carry_the_country():
    assert ids.PLACE_NAMESPACES["nz"] == ("np", "cp")
    assert ids.country_place_id("nz", "cp", "Kaimanawa") == "nz-cp-kaimanawa"
    assert ids.country_place_id("nz", "np", "Arthur's Pass") == "nz-np-arthurs-pass"
    with pytest.raises(ValueError):
        ids.country_place_id("nz", "lvo", "Kaimanawa")
    for identifier in ("nz-np-tongariro", "poi-nz-tongariro-whakapapa", "trail-nz-fiordland-x"):
        assert ids.country_of(identifier) == "nz"


def test_huts_and_conservation_parks_are_pinned_to_their_source_keys(tmp_path):
    registry = ids.Registry(tmp_path / "places.json")
    first = registry.resolve("napalis:2793445", "nz-cp-kaimanawa")
    assert registry.resolve("napalis:2793445", "nz-cp-renamed") == first == "nz-cp-kaimanawa"
    assert registry.resolve("napalis:1", "nz-cp-kaimanawa", qualifier="waikato") == (
        "nz-cp-kaimanawa-waikato"
    )
    pois = ids.Registry(tmp_path / "pois.json")
    hut = ids.country_poi_id(pois, "nz", "tongariro", "doc:asset/100043686", "Mangatepopo Hut")
    assert hut == "poi-nz-tongariro-mangatepopo-hut"
    assert pois.owner(hut) == "doc:asset/100043686"


# MARK: - Regions


@pytest.mark.parametrize(
    ("regc", "iso", "book"),
    [
        ("01", "NTL", "northIsland"), ("02", "AUK", "northIsland"), ("03", "WKO", "northIsland"),
        ("04", "BOP", "northIsland"), ("05", "GIS", "northIsland"), ("06", "HKB", "northIsland"),
        ("07", "TKI", "northIsland"), ("08", "MWT", "northIsland"), ("09", "WGN", "northIsland"),
        ("12", "WTC", "upperSouthIsland"), ("13", "CAN", "upperSouthIsland"),
        ("16", "TAS", "upperSouthIsland"), ("17", "NSN", "upperSouthIsland"),
        ("18", "MBH", "upperSouthIsland"),
        ("14", "OTA", "lowerSouthIsland"), ("15", "STL", "lowerSouthIsland"),
    ],
)
def test_every_region_has_its_code_and_book(regc, iso, book):
    assert rules.iso_code(regc) == iso
    assert rules.subdivision(iso) == f"NZ-{iso}"
    assert rules.passport_region(iso) == book


def test_outside_any_region_only_the_chathams_count():
    assert rules.iso_code("99", -176.5) == "CIT"
    assert rules.iso_code("99", 166.1) is None  # the subantarctic islands
    assert rules.passport_region("CIT") is None
    assert rules.time_zone(["CIT"]) == "Pacific/Chatham"
    assert rules.time_zone(["CAN", "WTC"]) == rules.time_zone([]) == "Pacific/Auckland"


def test_regions_are_read_with_the_chathams_apart(tmp_path):
    def polygon(west, south):
        return [[[west, south], [west + 1, south], [west + 1, south + 1], [west, south + 1],
                 [west, south]]]

    path = tmp_path / "regions.geojson"
    path.write_text(json.dumps({"features": [
        {"properties": {"REGC_code": "13"},
         "geometry": {"type": "Polygon", "coordinates": polygon(171, -44)}},
        {"properties": {"REGC_code": "99"},
         "geometry": {"type": "MultiPolygon",
                      "coordinates": [polygon(-177, -44.5), polygon(166, -51)]}},
    ]}))
    regions = fetching.read_regions(path)
    assert set(regions) == {"CAN", "CIT"} and len(regions["CIT"]) == 1


# MARK: - The second tier


@pytest.mark.parametrize(
    ("name", "shown", "designation"),
    [
        ("Kaimanawa Forest Park", "Kaimanawa", "Forest Park"),
        ("Ahuriri Conservation Park", "Ahuriri", "Conservation Park"),
        ("Lake Sumner (Hoka Kura) Forest Park", "Lake Sumner (Hoka Kura)", "Forest Park"),
        ("Waipoua Forest (Pt Northland Conservation Park)", "Waipoua Forest", "Conservation Park"),
        ("Maungataniwha Forest  (Pt Northland Conservation Park)", "Maungataniwha Forest",
         "Conservation Park"),
        ("Korowai/Torlesse Tussocklands Park", "Korowai/Torlesse Tussocklands Park",
         "Conservation Park"),
    ],
)
def test_a_designation_comes_off_a_conservation_parks_name(name, shown, designation):
    assert rules.display_name(name) == (shown, designation)


def test_northlands_forests_name_the_park_they_belong_to():
    assert rules.part_of("Waipoua Forest (Pt Northland Conservation Park)") == (
        "Northland Conservation Park"
    )
    assert rules.part_of("Ruapekapeka Forest (Pt Northland Cons. Park)") == (
        "Northland Conservation Park"
    )
    assert rules.part_of("Kaimanawa Forest Park") is None


def test_a_parcel_joins_the_park_it_is_named_after():
    parks = ["North-west Nelson Forest Park", "Mount Richmond Forest Park"]
    name = "Conservation Park - North West Nelson Forest Park - Takaka River - Cobb Dam Road"
    assert rules.is_parcel(name)
    assert rules.parent_of(name, parks) == "North-west Nelson Forest Park"
    assert rules.parent_of("Conservation Park - Onekaka River", parks) is None
    assert not rules.is_parcel("Kaimanawa Forest Park")


def test_only_the_recorded_area_is_a_fact():
    assert rules.recorded_hectares({"Recorded_Area": 75956.9}) == 75956.9
    assert rules.recorded_hectares({"Recorded_Area": None, "Shape__Area": 1.2e10}) is None
    assert rules.recorded_hectares({"Recorded_Area": 0}) is None


def _area(napalis, name, section, ring, area_m2, recorded=None):
    return {
        "type": "Feature",
        "geometry": {"type": "Polygon", "coordinates": [[*ring, ring[0]]]},
        "properties": {"NaPALIS_ID": napalis, "Name": name, "Section": section,
                       "Shape__Area": area_m2, "Recorded_Area": recorded,
                       "Start_Date": -1967976000000},
    }


def _ring(west, south, size):
    return [[west, south], [west + size, south], [west + size, south + size], [west, south + size]]


def test_records_are_read_with_parcels_joined_and_slivers_left_out(tmp_path):
    def collection(*features):
        return json.dumps({"type": "FeatureCollection", "features": list(features)})

    (tmp_path / "national-parks.geojson").write_text(collection(
        _area(2793719, "Tongariro National Park", "S4_NATIONAL_PARK", _ring(175.5, -39.3, 0.3),
              7.9e8, 78623.2),
    ))
    (tmp_path / "conservation-parks.geojson").write_text(collection(
        _area(2803462, "North-west Nelson Forest Park", "S19_CONSERVATION_PARK",
              _ring(172.3, -41.0, 0.2), 2.9e8, 28332.3),
        _area(4185788, "Conservation Park - North West Nelson Forest Park - Takaka River",
              "S19_CONSERVATION_PARK", _ring(172.6, -41.0, 0.05), 2.6e7, 2586.4),
        _area(9557, "Wires Road Access", "S19_CONSERVATION_PARK", _ring(175.0, -38.0, 0.001),
              800.0, 0.08),
    ))
    areas = fetching.read_areas(tmp_path)
    assert set(areas) == {"2793719", "2803462", "9557"}
    nelson = areas["2803462"]
    assert len(nelson.polygons) == 2 and nelson.recorded_hectares == 30918.7
    assert [area.napalis_id for area in fetching.second_tier(areas)] == ["2803462"]
    assert [area.name for area in fetching.left_out(areas)] == ["Wires Road Access"]


# MARK: - Tracks


@pytest.mark.parametrize(
    ("web", "asset", "category", "band"),
    [
        ("Easy access (wheelchair)", "Short Walk (disabled)", "Wheelchair-accessible short walk",
         "easy"),
        ("Short walk", "Short Walk", "Easy short walk", "easy"),
        ("Walking track", "Walking Track", "Easy to intermediate walking track", "moderate"),
        ("Great walk/easy tramping track", "Great Walk", "Intermediate tramping track",
         "moderatelyStrenuous"),
        ("Great walk/easy tramping track", "Easy Tramping Track", "Intermediate tramping track",
         "moderatelyStrenuous"),
        ("Tramping track", "Tramping Track", "Advanced tramping track", "strenuous"),
        ("Route", "Route", "Expert route", "veryStrenuous"),
        (None, "Tramping Track", "Advanced tramping track", "strenuous"),
        (None, "Cycle Track", None, None),
    ],
)
def test_docs_track_labels_read_as_its_six_categories(web, asset, category, band):
    assert rules.track_category(web, asset) == category
    assert rules.band(category) == band


def test_the_six_categories_map_to_bands_the_app_knows():
    assert len(rules.CATEGORIES) == 6
    assert set(rules.CATEGORIES.values()) <= {
        "easy", "moderate", "moderatelyStrenuous", "strenuous", "veryStrenuous",
    }
    grade = rules.track_grade("Expert route")
    assert grade["grade"] == "Expert route" and grade["publisher"] == "Department of Conservation"
    assert grade["sourceURL"] == rules.TRACK_CATEGORIES_URL


@pytest.mark.parametrize(
    ("values", "allowed"),
    [
        (["No Dogs"], False), (["No Dogs", "No Dogs"], False),
        (["Dogs on a leash only"], True), (["Dogs allowed - under control"], True),
        (["Dogs with DOC permit -hunting"], None),
        (["No Dogs,Dogs with DOC permit -hunting"], None),
        (["No Dogs", "Dogs on a leash only"], None), ([None], None),
    ],
)
def test_dogs_are_allowed_only_where_every_record_says_so(values, allowed):
    assert rules.dogs_allowed(values) is allowed


def test_track_names_lose_the_asset_prefix_and_spell_out_track():
    assert rules.track_name("T3:Puriri Track Off Cathedral Cove Walk") == (
        "Puriri Track Off Cathedral Cove Walk"
    )
    assert rules.track_name("Marokopa Falls Tk") == "Marokopa Falls Track"
    assert rules.track_name("Milford Tk - Clinton Hut Jcn To Bus Stop") == (
        "Milford Track - Clinton Hut Jcn To Bus Stop"
    )
    assert rules.track_base("Milford Track - Clinton Hut Jcn To Bus Stop") == "Milford Track"
    assert rules.track_base("Heaphy Track -Lewis Shelter To Mackay Hut") == "Heaphy Track"
    assert rules.track_base("Te Papa-Kura Walk") is None
    # A first part that names no track is no track; DOC's abbreviations are its own.
    assert rules.track_base("Track - Maori Beach To Port William") is None
    assert rules.without_generic_prefix("Track - Maori Beach To Port William") == (
        "Maori Beach To Port William"
    )
    assert rules.track_base("Atct - Marahau To Inland Track Junction") == (
        "Abel Tasman Coast Track"
    )
    assert rules.site_of("MILFRDTK-TK03") == "MILFRDTK"
    assert rules.site_of("AORAKILB-RD00-TP10") == "AORAKILB-RD00"


def _track(floc, name, asset, web, line, status="OPEN", public="Yes", dogs="No Dogs"):
    return {
        "type": "Feature",
        "geometry": {"type": "LineString", "coordinates": line},
        "properties": {
            "FlocID": floc, "TechObjectName": name, "SubObjectType": asset,
            "CharName2": "USER_STATUS", "CharValue2": status,
            "CharName3": "WEB_CATEGORY_TRACK", "CharValue3": web,
            "CharName6": "WEB_DOGS_ALLOWED", "CharValue6": dogs,
            "CharName14": "PUBLIC_USE", "CharValue14": public,
        },
    }


@pytest.fixture
def track_features():
    great = "Great walk/easy tramping track"
    return [
        _track("MILFRDTK-TK01", "Milford Tk - Clinton Hut Jcn To Bus Stop", "Great Walk", great,
               [[167.80, -44.90], [167.82, -44.88], [167.84, -44.86]]),
        _track("MILFRDTK-TK02", "Milford Tk - Marlenes Ck To Mintaro Hut", "Great Walk", great,
               [[167.84, -44.86], [167.86, -44.84], [167.88, -44.82]]),
        _track("MILFRDRJ-TK03", "Key Summit Tk", "Great Walk", great,
               [[168.10, -44.80], [168.11, -44.79], [168.12, -44.78]]),
        _track("DARRANEM-TK04", "Tutoko Valley Tk", "Tramping Track", "Tramping track",
               [[167.95, -44.70], [167.96, -44.69], [167.97, -44.68]], status="CLSD"),
        _track("DARRANEM-TK05", "Gertrude Valley Cycle", "Cycle Track", None,
               [[167.95, -44.70], [167.96, -44.69], [167.97, -44.68]]),
        _track("ELSEWHER-TK01", "Far Away Track", "Walking Track", "Walking track",
               [[175.0, -39.0], [175.01, -39.01], [175.02, -39.02]]),
    ]


def test_sections_of_one_track_are_joined_and_closed_tracks_left_out(track_features):
    park = {"id": "nz-np-fiordland"}
    polygons = [[[(167.0, -45.5), (168.5, -45.5), (168.5, -44.0), (167.0, -44.0)]]]
    found = {route.name: route for route in tracks.routes(park, track_features, polygons)}
    assert set(found) == {"Milford Track", "Key Summit Track"}
    milford = found["Milford Track"]
    assert milford.key == "doc:MILFRDTK/milfordtrack" and len(milford.segments) == 2
    assert milford.source == "doc"
    assert milford.extra[tracks.GRADE_KEY]["grade"] == "Intermediate tramping track"
    assert milford.extra["dogsAllowed"] is False
    assert found["Key Summit Track"].key == "doc:MILFRDRJ-TK03"


def test_sections_that_disagree_leave_the_category_unsaid():
    records = [
        {"SubObjectType": "Tramping Track", "CharName3": "WEB_CATEGORY_TRACK",
         "CharValue3": "Tramping track"},
        {"SubObjectType": "Route", "CharName3": "WEB_CATEGORY_TRACK", "CharValue3": "Route"},
    ]
    assert tracks.agreed_category(records) is None
    assert tracks.agreed_category(records[:1]) == "Advanced tramping track"


def test_a_doc_track_is_measured_into_a_record_with_its_category(track_features, tmp_path):
    park = {"id": "nz-np-fiordland"}
    polygons = [[[(167.0, -45.5), (168.5, -45.5), (168.5, -44.0), (167.0, -44.0)]]]
    route = next(r for r in tracks.routes(park, track_features, polygons)
                 if r.name == "Milford Track")
    registry = ids.Registry(tmp_path / "trails.json")
    record = abroad_trails.trail_record(
        "nz", park, route, lambda lon, lat: None, [], [], registry,
    )
    assert record is not None
    assert record["id"] == "trail-nz-fiordland-milford-track"
    assert record["source"] == "doc" and record["dogsAllowed"] is False
    assert record[tracks.GRADE_KEY]["grade"] == "Intermediate tramping track"
    # Not a field the app reads yet: the app has no TrailGrade.System for DOC.
    assert registry.owner(record["id"]) == "doc:MILFRDTK/milfordtrack"


# MARK: - Huts, campsites and visitor centres


def _asset(name, kind, x, y, sort, *characteristics, status="OPEN", public="Yes"):
    properties = {"TechObjectName": name, "SubObjectType": kind, "SortField": sort,
                  "CharName2": "USER_STATUS", "CharValue2": status,
                  "CharName14": "PUBLIC_USE", "CharValue14": public}
    for index, (key, value) in enumerate(characteristics, start=3):
        properties[f"CharName{index}"] = key
        properties[f"CharValue{index}"] = value
    return {"type": "Feature", "geometry": {"type": "Point", "coordinates": [x, y]},
            "properties": properties}


def test_a_hut_and_a_campsite_are_described_from_docs_own_record():
    hut = _asset("Mangatepopo Hut", "Serviced Hut", 175.6, -39.1, 1,
                 ("WEB_HUT_BUNKS", "20 each"))["properties"]
    assert rules.hut_summary(hut, {"bookable": "Yes"}) == "Serviced Hut · 20 bunks · Bookable"
    assert rules.hut_summary({"SubObjectType": "BUIIN-BUIN"}) is None
    camp = _asset("Iris Burn Campsite", "Great Walk", 167.5, -45.4, 2,
                  ("WEB_NUM_SITES_NON_POWER", "15"), ("WEB_NUM_SITES_POWER", "0"))["properties"]
    assert rules.campsite_summary(camp) == "Great Walk campsite · 15 sites"
    assert rules.characteristic(camp, "WEB_NUM_SITES_POWER") == "0"
    assert rules.is_open_to_the_public(camp)
    assert not rules.is_open_to_the_public({**camp, "CharValue2": "CLSD"})


# MARK: - Rail and documents


def test_an_extract_read_becomes_routes_with_their_geometry():
    elements = [
        {"type": "relation", "id": 1, "tags": {"route": "train", "name": "TranzAlpine"},
         "members": [{"type": "way", "ref": 10, "role": ""},
                     {"type": "node", "ref": 20, "role": "stop"}]},
        {"type": "relation", "id": 2, "tags": {"type": "route_master"}, "members": []},
        {"type": "way", "id": 10, "geometry": [{"lat": -43.5, "lon": 172.6},
                                                {"lat": -42.9, "lon": 171.6}]},
        {"type": "node", "id": 20, "lat": -42.94, "lon": 171.56,
         "tags": {"railway": "station", "name": "Arthur's Pass"}},
    ]
    routes = fetching.as_out_geom(elements)
    assert len(routes) == 1 and routes[0]["id"] == 1
    way, node = routes[0]["members"]
    assert way["geometry"][0] == {"lat": -43.5, "lon": 172.6}
    assert (node["lat"], node["lon"]) == (-42.94, 171.56)


def test_pdf_links_on_a_doc_page_are_made_absolute_once_each():
    page = "https://www.doc.govt.nz/parks-and-recreation/places-to-go/fiordland/places/x/"
    html = (
        '<a href="/globalassets/documents/fiordland-day-walks.pdf">Fiordland day&nbsp;walks '
        '(PDF, 2,345K)</a> <a href="/globalassets/documents/fiordland-day-walks.pdf">again</a>'
        '<a href="https://example.org/page">not a pdf</a>'
    )
    assert fetching.pdf_links(page, html) == [{
        "title": "Fiordland day walks",
        "url": "https://www.doc.govt.nz/globalassets/documents/fiordland-day-walks.pdf",
    }]


def test_the_extract_is_named_per_country():
    japan, new_zealand = osm_pbf.extract_for("jp"), osm_pbf.extract_for("nz")
    assert japan.filename == osm_pbf.JAPAN_FILE and japan.source == osm_pbf.SOURCE
    assert new_zealand.url.endswith("/australia-oceania/new-zealand-latest.osm.pbf")
    assert new_zealand.source != japan.source
    with pytest.raises(ValueError):
        osm_pbf.extract_for("xx")


# MARK: - Wikidata


def test_a_conservation_park_never_takes_a_national_parks_item():
    others = [
        {"qid": "Q1", "coord": (-39.2, 175.6), "names": {"tongariro"},
         "article": "https://en.wikipedia.org/wiki/Tongariro_National_Park"},
        {"qid": "Q2", "coord": (-39.2, 176.0), "names": {"kaimanawa-forest-park"},
         "article": "https://en.wikipedia.org/wiki/Kaimanawa_Forest_Park"},
    ]
    found = wiki.own_matches(
        [
            ("np", "np", "Tongariro National Park", (-39.2, 175.6), 20.0),
            ("cp", "cp", "Kaimanawa Forest Park", (-39.1, 176.0), 20.0),
            ("cp-wrong", "cp", "Tongariro", (-39.2, 175.6), 20.0),
        ],
        others,
    )
    assert found["cp"]["qid"] == "Q2"
    # The park's own article refuses the conservation park, so the park keeps its item.
    assert "cp-wrong" not in found and found["np"]["qid"] == "Q1"
    # An item two conservation parks reach describes neither.
    twice = wiki.own_matches(
        [("a", "cp", "Kaimanawa Forest Park", (-39.1, 176.0), 20.0),
         ("b", "cp", "Kaimanawa Forest Park", (-39.2, 176.1), 20.0)],
        others,
    )
    assert twice == {}


# MARK: - A build


def _point_feature(x, y, **properties):
    return {"type": "Feature", "geometry": {"type": "Point", "coordinates": [x, y]},
            "properties": properties}


@pytest.fixture
def new_zealand(tmp_path, monkeypatch):
    """A raw store and content folder with one national park, two conservation parks,
    two regions, a hut, a campsite and a visitor centre."""
    raw = tmp_path / "raw" / "2026-11-17"

    def write(source, name, payload):
        directory = raw / source
        directory.mkdir(parents=True, exist_ok=True)
        (directory / name).write_text(json.dumps(payload))

    def collection(*features):
        return {"type": "FeatureCollection", "features": list(features)}

    write(fetching.PCL, "national-parks.geojson", collection(
        _area(2793719, "Tongariro National Park", "S4_NATIONAL_PARK", _ring(175.4, -39.4, 0.4),
              7.9e8, 78623.2),
    ))
    write(fetching.PCL, "conservation-parks.geojson", collection(
        _area(2793445, "Kaimanawa Forest Park", "S19_CONSERVATION_PARK",
              _ring(175.9, -39.4, 0.3), 7.5e8, 75956.9),
        _area(5090, "Waipoua Forest (Pt Northland Conservation Park)", "S19_CONSERVATION_PARK",
              _ring(173.5, -35.7, 0.1), 1.2e8, 12410.8),
        _area(9557, "Wires Road Access", "S19_CONSERVATION_PARK", _ring(175.0, -38.0, 0.001),
              800.0, 0.08),
    ))
    write(fetching.PCL, "counts.json", {"nationalParks": 13, "conservationParks": 67,
                                       "teUrewera": 0})

    def region(code, west, south, east, north):
        ring = [[west, south], [east, south], [east, north], [west, north], [west, south]]
        return {"type": "Feature", "properties": {"REGC_code": code},
                "geometry": {"type": "Polygon", "coordinates": [ring]}}

    write(fetching.REGIONS, "regions.geojson", collection(
        region("08", 175.0, -40.0, 175.7, -38.5),  # Manawatū-Whanganui
        region("03", 175.7, -40.0, 177.0, -38.5),  # Waikato
        region("01", 172.5, -36.5, 174.5, -34.3),  # Northland
    ))
    write(fetching.FACILITIES, "huts.geojson", collection(
        _asset("Mangatepopo Hut", "Serviced Hut", 175.55, -39.15, 100040290,
               ("WEB_HUT_BUNKS", "20 each")),
        _asset("Closed Hut", "Standard Hut", 175.56, -39.16, 100040291, status="CLSD"),
        _asset("Outside Hut", "Standard Hut", 176.1, -39.2, 100040292),
    ))
    write(fetching.FACILITIES, "huts-web.geojson", collection(_point_feature(
        175.55, -39.15, name="Mangatepopo Hut", assetId=100040290, bookable="Yes",
        staticLink="https://www.doc.govt.nz/link/abc.aspx",
    )))
    write(fetching.FACILITIES, "campsites.geojson", collection(
        _asset("Whakapapa Holiday Park", "Standard", 175.6, -39.2, 100065488,
               ("WEB_NUM_SITES_NON_POWER", "10")),
    ))
    write(fetching.FACILITIES, "campsites-web.geojson", collection())
    write(fetching.FACILITIES, "visitor-centres.geojson", collection(
        _point_feature(175.55, -39.21, OfficeID=1, Name="Whakapapa", IsActive=1,
                       FullNameLabel="Whakapapa Visitor Centre", Town="Whakapapa"),
        _point_feature(174.76, -36.85, OfficeID=2, Name="Auckland", IsActive=1,
                       FullNameLabel="Auckland Visitor Centre", Town="Auckland"),
    ))

    content_dir = tmp_path / "content" / "countries" / "nz"
    (content_dir / "guides").mkdir(parents=True)
    (content_dir / "national-parks.json").write_text(json.dumps({"parks": [{
        "id": "nz-np-tongariro", "name": "Tongariro", "napalisId": "2793719",
        "passportRegion": "northIsland",
        "docPage": "https://www.doc.govt.nz/parks-and-recreation/places-to-go/"
                   "central-north-island/places/tongariro-national-park/",
    }]}))
    (content_dir / "guides" / "nz-np-tongariro.json").write_text(json.dumps({
        "placeID": "nz-np-tongariro",
        "summary": "Three volcanoes.",
        "facts": {"establishedYear": 1887, "bestSeasons": ["summer"]},
        "sights": [{"name": "Tama Lakes", "note": "Crater lakes.", "location": [-39.2, 175.6]},
                   {"name": "Nowhere", "location": [61.5, 8.7]}],
        "themes": ["theme-volcanoes"],
    }))
    (tmp_path / "content" / "themes.json").write_text(json.dumps({"themes": [
        {"id": "theme-volcanoes"},
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


def test_a_build_on_the_fixture_gives_records_the_app_decodes(new_zealand):
    images = new_zealand / "images"
    images.mkdir()
    share = assembly.assemble(BuildContext(online=False, images_dir=images))
    places = {place["id"]: place for place in share.places}

    park = places["nz-np-tongariro"]
    assert park["kind"] == "nationalPark" and park["designation"] == "National Park"
    assert park["agency"] == "conservationDepartmentNZ" and park["country"] == "NZ"
    assert park["subdivisions"][0] in ("NZ-MWT", "NZ-WKO")
    assert park["passportRegion"] == "northIsland"
    assert park["timeZoneID"] == "Pacific/Auckland"
    # The guide gives no area, so DOC's recorded area for the land stands in.
    assert park["facts"] == {
        "establishedYear": 1887, "bestSeasons": ["summer"], "areaHectares": 78623,
    }
    assert park["officialURL"].startswith("https://www.doc.govt.nz/")
    assert park["summarySource"] == "Unigrids" and park["themes"] == ["theme-volcanoes"]

    kaimanawa = places["nz-cp-kaimanawa"]
    assert kaimanawa["kind"] == "conservationPark" and kaimanawa["name"] == "Kaimanawa"
    assert kaimanawa["designation"] == "Forest Park"
    assert kaimanawa["subdivisions"] == ["NZ-WKO"] and kaimanawa["passportRegion"] == "northIsland"
    # The recorded area is a fact; Start_Date is a land record's date, never the founding.
    assert kaimanawa["facts"] == {"areaHectares": 75957}
    waipoua = places["nz-cp-waipoua-forest"]
    assert waipoua["designation"] == "Conservation Park"
    assert waipoua["subdivisions"] == ["NZ-NTL"]
    assert "nz-cp-wires-road-access" not in places
    assert set(places) == set(share.boundaries)

    pois = {poi["name"]: poi for poi in share.pois}
    assert pois["Tama Lakes"]["rank"] == 1 and pois["Tama Lakes"]["id"] == (
        "poi-nz-tongariro-tama-lakes"
    )
    hut = pois["Mangatepopo Hut"]
    assert hut["kind"] == "hut" and hut["url"] == "https://www.doc.govt.nz/link/abc.aspx"
    assert hut["summary"] == "Serviced Hut · 20 bunks · Bookable"
    assert "Closed Hut" not in pois and "Outside Hut" not in pois and "Nowhere" not in pois
    assert pois["Whakapapa Holiday Park"]["kind"] == "campground"
    assert pois["Whakapapa Visitor Centre"]["placeID"] == "nz-np-tongariro"
    assert "Auckland Visitor Centre" not in pois

    # No US fallbacks: every place carries its own country, agency, region, zone and book.
    for place in share.places:
        assert place["country"] == "NZ" and place["agency"] == "conservationDepartmentNZ"
        assert place["passportRegion"] in rules.PASSPORT_REGIONS
        assert place["timeZoneID"] in ("Pacific/Auckland", "Pacific/Chatham")
        assert place["subdivisions"] and all(s.startswith("NZ-") for s in place["subdivisions"])
        assert "states" not in place
    assert share.expects_summary == {"nz-np-tongariro"}
    assert {registry.path.name for registry in share.registries} == {
        "places.json", "pois.json", "trails.json",
    }
    # No raw tracks or elevation tiles in the fixture, and offline: none invented.
    assert share.trails == [] and "highestElevationMetres" not in park["facts"]
    assert share.registries[0].owner("nz-cp-kaimanawa") == "napalis:2793445"


# MARK: - The package


def test_new_zealand_keeps_the_country_contract():
    new_zealand = countries.load("nz")
    assert new_zealand.CODE == "nz" and new_zealand.NAME == "New Zealand"
    assert "nz" in countries.KNOWN and countries.DEFAULT == ("us",)
    places = [{"kind": "nationalPark", "summary": "…"}, {"kind": "conservationPark"}]
    note = new_zealand.manifest_note(places)
    assert note.startswith("New Zealand: all 1 national parks with a guide and 1 conservation")
    assert "not affiliated with DOC" in note


def test_new_zealand_is_registered_abroad():
    assert "nz" in abroad_outlines.COUNTRIES and "nz" in abroad_trails.COUNTRIES
    assert abroad_packs.COUNTRY_NAMES["nz"] == "New Zealand"
    assert "DOC logo" in abroad_packs.NOT_AFFILIATED["nz"]
    assert abroad_outlines.COUNTRY_SOURCES["nz"] == ("nz-pcl", "national-parks.geojson")
    assert {park["id"] for park in abroad_outlines.park_list("nz")} == {
        park["id"] for park in content.parks()
    }
