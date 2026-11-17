"""Norway's rules and records, on small fixtures and no network.

The rules are the ones a wrong answer would ship quietly: which county and region a place
belongs to, which language an official name is in, what is left of a name once its
designation comes off, which reserves are big enough to carry, and that every identifier
goes through a registry keyed on its source's own id.
"""

from __future__ import annotations

import json

import pytest

from unigrids_pipeline import config, countries, ids
from unigrids_pipeline.countries import BuildContext
from unigrids_pipeline.countries.no import assembly, content, fetching, rules, transport, wiki

# MARK: - Counties and regions


def test_counties_are_read_off_municipality_numbers():
    kommune = "Vågå (3435),Luster (4644),Lom (3434),Vang (3454),Årdal (4643)"
    assert rules.municipality_numbers(kommune) == ["3435", "4644", "3434", "3454", "4643"]
    assert rules.county_codes(kommune) == ["34", "46"]


def test_a_municipality_name_with_its_own_parentheses_is_read_by_number():
    assert rules.county_codes("Herøy (Nordland) (1818)") == ["18"]
    assert rules.county_codes("Guovdageaidnu - Kautokeino (5612),Kárášjohka - Karasjok (5610)") == [
        "56"
    ]


def test_svalbard_is_county_21_and_jan_mayen_is_no_county():
    assert rules.county_codes("Spitsbergen (2111)") == ["21"]
    assert rules.county_codes("Jan Mayen (2211)") == []
    assert rules.county_codes(None) == []


@pytest.mark.parametrize(
    ("county", "region"),
    [
        ("18", "northernNorway"), ("55", "northernNorway"), ("56", "northernNorway"),
        ("50", "trondelag"),
        ("11", "westernNorway"), ("15", "westernNorway"), ("46", "westernNorway"),
        ("03", "easternNorway"), ("31", "easternNorway"), ("32", "easternNorway"),
        ("33", "easternNorway"), ("34", "easternNorway"), ("39", "easternNorway"),
        ("40", "easternNorway"),
        ("42", "southernNorway"),
        ("21", "svalbard"),
    ],
)
def test_every_county_has_its_region(county, region):
    assert rules.region_of(county) == region
    assert rules.subdivision(county) == f"NO-{county}"


def test_every_county_has_a_region_and_a_name():
    assert set(rules.COUNTIES) == set(rules.REGION_OF_COUNTY)
    assert len(rules.COUNTIES) == 16


def test_the_region_is_the_county_holding_most_of_the_place():
    listed = ["34", "50", "15"]
    shares = {"34": 10, "50": 40, "15": 25}
    assert rules.main_county(listed, shares) == "50"
    assert rules.region_of(rules.main_county(listed, shares)) == "trondelag"
    assert rules.ordered_counties(listed, shares) == ["50", "15", "34"]


def test_without_shares_the_first_listed_county_decides():
    assert rules.main_county(["46", "34"], {}) == "46"
    assert rules.main_county([], {}) is None


def test_svalbard_is_its_own_region_whatever_the_shares():
    assert rules.main_county(["21"], {"18": 5}) == "21"


def _square(west: float, south: float, size: float) -> list:
    return [[[(west, south), (west + size, south), (west + size, south + size),
              (west, south + size)]]]


def test_county_shares_are_measured_by_area():
    counties = rules.Counties({"34": _square(8.0, 61.0, 1.0), "46": _square(7.0, 61.0, 1.0)})
    assert counties.at(61.5, 8.5) == "34"
    assert counties.at(61.5, 7.5) == "46"
    assert counties.at(60.0, 7.5) is None
    # A place three quarters in Innlandet and a quarter in Vestland.
    place = [[[(7.75, 61.2), (8.75, 61.2), (8.75, 61.8), (7.75, 61.8)]]]
    shares = counties.shares(place, among=["34", "46"])
    assert rules.main_county(["46", "34"], shares) == "34"
    assert shares["34"] > 2 * shares["46"]


def test_a_place_in_one_county_needs_no_sampling():
    counties = rules.Counties({"34": _square(8.0, 61.0, 1.0)})
    assert counties.shares(_square(20.0, 70.0, 0.1), among=["56"]) == {"56": 1}


# MARK: - Names


@pytest.mark.parametrize(
    ("official", "expected"),
    [
        ("Jotunheimen nasjonalpark", [("nb", "Jotunheimen nasjonalpark")]),
        (
            "Varangerhalvøya nasjonalpark/Várnjárgga álbmotmeahcci/ Varenkinniemen kansalistaras",
            [
                ("nb", "Varangerhalvøya nasjonalpark"),
                ("se", "Várnjárgga álbmotmeahcci"),
                ("fkv", "Varenkinniemen kansalistaras"),
            ],
        ),
        (
            "Anárjoga álbmotmeahcci/Anárjohka nasjonalpark",
            [("se", "Anárjoga álbmotmeahcci"), ("nb", "Anárjohka nasjonalpark")],
        ),
        (
            "Stabbursdalen nasjonalpark/Rávttošvuomi Álbmotmeahcci",
            [("nb", "Stabbursdalen nasjonalpark"), ("se", "Rávttošvuomi Álbmotmeahcci")],
        ),
        (
            "Junkerdal nasjonalpark/Juŋŋkaravuome nasjonalpárkka",
            [("nb", "Junkerdal nasjonalpark"), ("smj", "Juŋŋkaravuome nasjonalpárkka")],
        ),
        (
            "Sjunkhatten nasjonalpark/Dávga suoddjimpárkka",
            [("nb", "Sjunkhatten nasjonalpark"), ("smj", "Dávga suoddjimpárkka")],
        ),
        (
            "Lomsdal-Visten nasjonalpark/Njaarken vaarjelimmiedajve",
            [("nb", "Lomsdal-Visten nasjonalpark"), ("sma", "Njaarken vaarjelimmiedajve")],
        ),
        (
            "Blåfjella-Skjækerfjella/Låarte-Skæhkere nasjonalpark",
            [
                ("nb", "Blåfjella-Skjækerfjella nasjonalpark"),
                ("sma", "Låarte-Skæhkere nasjonalpark"),
            ],
        ),
        (
            "Lierne/Lijre nasjonalpark",
            [("nb", "Lierne nasjonalpark"), ("sma", "Lijre nasjonalpark")],
        ),
    ],
)
def test_official_names_are_tagged_with_their_language(official, expected):
    names, unknown = rules.local_names(official)
    assert [(name["language"], name["text"]) for name in names] == expected
    assert unknown == []


def test_a_form_no_rule_knows_is_reported_not_guessed():
    names, unknown = rules.local_names("Jotunheimen nasjonalpark/Jotunheimen")
    # The bare form takes the designation of no later form, so no rule can tag it.
    assert names == [{"language": "nb", "text": "Jotunheimen nasjonalpark"}]
    assert unknown == ["Jotunheimen"]


@pytest.mark.parametrize(
    ("name", "stripped"),
    [
        ("Dividalen landskapsvernområde", "Dividalen"),
        ("Dividalen", "Dividalen"),
        ("Fokstumyra naturreservat", "Fokstumyra"),
        ("Gråkletten naturresevat", "Gråkletten"),
        ("Sørkapp fuglereservat", "Sørkapp"),
        ("Laugen landskapsvernområde med tilhørende dyrelivsfredning", "Laugen"),
        ("Hjerkinn/Kongsvoll/Drivdalen landskapsvernområder", "Hjerkinn/Kongsvoll/Drivdalen"),
        ("Skardmodalen naturreservat/Skaalma eatnemedajve", "Skardmodalen/Skaalma"),
        ("Jotunheimen nasjonalpark", "Jotunheimen"),
        ("Store rekke og Hølvannet", "Store rekke og Hølvannet"),
        (
            "Mariafjellet - Skardbekken / Tjaetsiegaske",
            "Mariafjellet - Skardbekken / Tjaetsiegaske",
        ),
    ],
)
def test_a_designation_comes_off_a_name(name, stripped):
    assert rules.strip_designation(name) == stripped


# MARK: - Second tier


def test_reserves_of_ten_square_kilometres_or_more_are_carried():
    assert rules.carries_reserve({"SHAPE.STArea()": 10_000_000})
    assert rules.carries_reserve({"SHAPE.STArea()": 25_400_000.5})
    assert not rules.carries_reserve({"SHAPE.STArea()": 9_999_999})
    assert not rules.carries_reserve({})


def test_reserve_thresholds_are_counted_in_square_kilometres():
    areas = [4.9e6, 5e6, 9.9e6, 10e6, 24e6, 25e6, 300e6]
    assert rules.threshold_counts(areas) == {5: 6, 10: 4, 25: 2}


@pytest.mark.parametrize(
    ("verneform", "tier"),
    [
        ("Nasjonalpark", "np"), ("NasjonalparkSvalbard", "np"),
        ("Landskapsvernomraade", "lvo"), ("LandskapsvernomraadeDyrelivsfredning", "lvo"),
        ("Naturreservat", "nr"), ("NaturreservatSvalbard", "nr"), ("NaturreservatJanMayen", "nr"),
        ("Naturminne", None), ("MarintVerneomraade", None), (None, None),
    ],
)
def test_tiers_come_from_the_verneform(verneform, tier):
    assert rules.tier_of(verneform) == tier


def test_established_is_first_protection_never_the_regulation():
    # 1970-02-06 and 1975-12-19, as ArcGIS dates.
    first, regulation = 3110400000, 1103241600000
    assert rules.established_year({"foerstegangVernet": first, "vernedato": regulation}) == 1970
    # A current regulation's date is not when the area was protected: absent, not wrong.
    assert rules.established_year({"foerstegangVernet": None, "vernedato": 188179200000}) is None
    assert rules.established_year({}) is None
    # Before 1970 the milliseconds are negative.
    assert rules.year_of(-252460800000) == 1962


# MARK: - Identifiers


def test_second_tier_identifiers_are_pinned_to_the_naturvern_id(tmp_path):
    registry = ids.Registry(tmp_path / "places.json")
    proposed = ids.country_place_id("no", "lvo", "Dividalen")
    assert proposed == "no-lvo-dividalen"
    first = registry.resolve("naturvern:VV00000001", proposed, qualifier="troms")
    assert first == "no-lvo-dividalen"
    # A second area of the same name in another county is qualified, not merged.
    other = registry.resolve("naturvern:VV00000002", proposed, qualifier="nordland")
    assert other == "no-lvo-dividalen-nordland"
    registry.save()
    again = ids.Registry(tmp_path / "places.json")
    assert again.resolve("naturvern:VV00000002", "no-lvo-renamed") == "no-lvo-dividalen-nordland"


def test_points_of_interest_are_keyed_on_guide_and_osm_ids(tmp_path):
    registry = ids.Registry(tmp_path / "pois.json")
    sight = ids.country_poi_id(
        registry, "no", "jotunheimen", "guide:no-np-jotunheimen:Besseggen", "Besseggen"
    )
    hut = ids.country_poi_id(registry, "no", "jotunheimen", "osm:node/288156091", "Gjendebu")
    assert sight == "poi-no-jotunheimen-besseggen"
    assert hut == "poi-no-jotunheimen-gjendebu"
    renamed = ids.country_poi_id(
        registry, "no", "jotunheimen", "osm:node/288156091", "Gjendebu turisthytte"
    )
    assert renamed == hut


def test_park_slugs_are_the_content_ids_without_their_prefix():
    assert content.park_slug("no-np-jotunheimen") == "jotunheimen"
    assert all(park["id"].startswith("no-np-") for park in content.parks())
    assert len(content.parks()) == 48
    assert sum(1 for park in content.parks() if park["svalbard"]) == 7


# MARK: - Huts, rail and Wikidata


@pytest.mark.parametrize(
    ("tags", "summary"),
    [
        ({"operator": "DNT Oslo og Omegn"}, "DNT cabin"),
        ({"operator": "Den Norske Turistforening"}, "DNT cabin"),
        ({"brand": "DNT", "operator": "Årdal Turlag"}, "DNT cabin"),
        ({"operator": "Statskog"}, "Run by Statskog"),
        ({}, None),
    ],
)
def test_a_hut_is_described_by_who_runs_it(tags, summary):
    assert rules.hut_summary(tags) == summary


def _route(relation_id: int, ref: str, name: str, stops: list, ways: list, **tags) -> dict:
    members = [
        {"type": "way", "ref": 1000 + index, "role": "",
         "geometry": [{"lat": lat, "lon": lon} for lat, lon in way]}
        for index, way in enumerate(ways)
    ]
    members += [
        {"type": "node", "ref": node, "role": "stop", "lat": lat, "lon": lon}
        for node, lat, lon in stops
    ]
    return {"type": "relation", "id": relation_id, "members": members,
            "tags": {"route": "train", "ref": ref, "name": name, **tags}}


def test_rail_lines_join_their_relations_and_stations_learn_their_lines():
    track = [(59.91, 10.75), (60.0, 10.0), (60.39, 5.33)]
    routes = {
        relation["id"]: transport.Route(relation)
        for relation in (
            _route(1, "F4", "F4 Oslo S→Bergen", [(10, 59.91, 10.75), (11, 60.39, 5.33)], [track],
                   **{"from": "Oslo S", "to": "Bergen"}),
            _route(2, "F4", "F4 Bergen→Oslo S", [(11, 60.39, 5.33)], [track[::-1]]),
            _route(3, "62", "Tåg 62: Göteborg C => Töreboda", [(20, 57.7, 11.97)],
                   [[(57.7, 11.97), (58.6, 14.0)]]),
            _route(4, "", "Kirkenes–Bjørnevatnbanen", [(30, 69.7, 30.0)],
                   [[(69.7, 30.0), (69.66, 30.03)]], service="industrial"),
        )
    }

    def in_norway(latitude: float, longitude: float) -> bool:
        return latitude > 58.5

    lines, belongs = transport.build_lines(routes, in_norway)
    assert [line["name"] for line in lines] == ["F4 Oslo S–Bergen"]
    assert set(lines[0]) == {"name", "bbox", "paths"}
    assert belongs == {1: "F4 Oslo S–Bergen", 2: "F4 Oslo S–Bergen"}

    bergen = {"type": "node", "id": 5, "lat": 60.3903, "lon": 5.3331,
              "tags": {"railway": "station", "name": "Bergen"}}
    finse = {"type": "node", "id": 6, "lat": 60.60, "lon": 7.50,
             "tags": {"railway": "station", "name": "Finse"}}
    assert transport.station_lines(bergen, routes, belongs, {}) == ["F4 Oslo S–Bergen"]
    assert transport.station_lines(finse, routes, belongs, {}) == []
    # Finse's stop area holds a stop the route lists.
    areas = {"osm:node/6": {"osm:node/6", "osm:node/10"}}
    assert transport.station_lines(finse, routes, belongs, areas) == ["F4 Oslo S–Bergen"]
    entry = transport.station_entry(bergen, ["F4 Oslo S–Bergen"])
    assert entry == {
        "code": "osm:node/5", "name": "Bergen",
        "location": {"latitude": 60.3903, "longitude": 5.3331},
        "country": "NO", "lines": ["F4 Oslo S–Bergen"],
    }


def test_light_rail_and_subway_stations_are_not_railway_stations():
    def element(**tags):
        return {"type": "node", "id": 1, "lat": 60.0, "lon": 10.0, "tags": tags}

    assert transport.is_station(element(railway="station", name="Hamar"))
    assert transport.is_station(element(public_transport="station", train="yes"))
    assert not transport.is_station(element(railway="station", station="subway"))
    assert not transport.is_station(element(railway="station", station="light_rail"))
    assert not transport.is_station(element(public_transport="station", bus="yes"))
    # Closed, a museum line's, or only planned.
    assert not transport.is_station(element(railway="station", end_date="1963-05-01"))
    assert not transport.is_station(element(railway="station", **{"railway:preserved": "yes"}))
    assert not transport.is_station(
        element(public_transport="station", train="yes", **{"proposed:railway": "station"})
    )


def test_distance_to_a_park_is_zero_inside_and_to_the_edge_outside():
    park = _square(10.0, 60.0, 1.0)
    assert transport.distance_to_outline_km((60.5, 10.5), park) == 0.0
    # One degree of latitude south of the park's southern edge.
    assert transport.distance_to_outline_km((59.0, 10.5), park) == pytest.approx(111.2, abs=0.5)


def _naturbase(qid: str, naturvern_id: str, title: str | None) -> dict:
    binding = {
        "item": {"value": f"http://www.wikidata.org/entity/{qid}"},
        "id": {"value": naturvern_id},
        "coord": {"value": "Point(15.5 68.5)"},
    }
    if title:
        binding["article"] = {"value": f"https://en.wikipedia.org/wiki/{title.replace(' ', '_')}"}
    return binding


def test_a_landscape_never_takes_a_national_parks_article():
    # As Wikidata has it: Møysalen National Park's item carries the landscape's ID.
    index = wiki.naturbase_index([
        _naturbase("Q1276455", "VV00002195", "Møysalen National Park"),
        _naturbase("Q100", "VV00000100", "Pasvik Nature Reserve"),
        _naturbase("Q101", "VV00000101", "Maridalen"),
    ])
    matches = wiki.own_matches(
        [
            ("VV00002195", "lvo", "Møysalen", (68.51, 15.37)),
            ("VV00000100", "nr", "Pasvik", None),
            ("VV00000101", "lvo", "Maridalen", None),
        ],
        index,
        [],
    )
    assert sorted(matches) == ["VV00000100", "VV00000101"]


def test_an_item_two_places_reach_is_neither_places():
    index = wiki.naturbase_index([
        _naturbase("Q7", "VV1", "Trillemarka"),
        _naturbase("Q7", "VV2", "Trillemarka"),
        _naturbase("Q8", "VV3", "Jotunheimen National Park"),
    ])
    matches = wiki.own_matches(
        [("VV1", "nr", "Trillemarka", None), ("VV2", "lvo", "Trillemarka", None),
         ("VV3", "np", "Jotunheimen", None)],
        index,
        [],
    )
    assert list(matches) == ["VV3"]


@pytest.mark.parametrize(
    ("title", "tier"),
    [
        ("Møysalen National Park", "np"),
        ("Rondane nasjonalpark", "np"),
        ("Utladalen Landscape Protection Area", "lvo"),
        ("Lemmingvær Landscape Conservation Area", "lvo"),
        ("Dunøyane Bird Sanctuary", "nr"),
        ("Stabbursnes Nature Reserve", "nr"),
        ("Maridalen", None),
        (None, None),
    ],
)
def test_a_title_names_the_kind_of_place_it_is_about(title, tier):
    assert wiki.title_tier(title) == tier


def test_wikidata_matches_by_naturbase_id_else_by_name_and_place():
    naturbase = [{
        "item": {"value": "http://www.wikidata.org/entity/Q1578584"},
        "id": {"value": "VV00001869"},
        "article": {"value": "https://en.wikipedia.org/wiki/Jotunheimen_National_Park"},
        "coord": {"value": "Point(8.3 61.6)"},
    }]
    others = [{
        "item": {"value": "http://www.wikidata.org/entity/Q4567091"},
        "label": {"value": "Rinnleiret naturreservat"},
        "coord": {"value": "Point(11.4 63.8)"},
    }]
    index, candidates = wiki.naturbase_index(naturbase), wiki.candidates(others)
    assert wiki.match("VV00001869", "Jotunheimen", None, index, candidates)["qid"] == "Q1578584"
    assert wiki.match("VV9", "Rinnleiret", (63.81, 11.41), index, candidates)["qid"] == "Q4567091"
    # The same name far away is someone else.
    assert wiki.match("VV9", "Rinnleiret", (69.0, 18.0), index, candidates) is None
    assert wiki.article_title("https://en.wikipedia.org/wiki/Gress%C3%A5moen_National_Park") == (
        "Gressåmoen National Park"
    )
    assert wiki.file_name(
        "http://commons.wikimedia.org/wiki/Special:FilePath/Prins-karls-forrland%20pho.jpg"
    ) == "Prins-karls-forrland pho.jpg"


def test_a_lead_is_cut_to_a_card():
    extract = "One. Two (/ˈtuː/) words. Three. Four."
    assert wiki.lead(extract) == "One. Two words. Three."


# MARK: - Photographs


@pytest.mark.parametrize(
    ("licence", "public"),
    [("CC BY-SA 4.0", False), ("Public domain", True), ("CC0", True), ("GFDL", False)],
)
def test_every_photograph_keeps_its_credit_and_licence(licence, public):
    entry = assembly.photo_entry(
        {"url": "u", "credit": "Kari Nordmann, via Wikimedia Commons", "licence": licence},
        asset_name="no-np-x-a.jpg",
    )
    assert entry is not None
    assert entry["credit"] == "Kari Nordmann, via Wikimedia Commons"
    assert entry["isPublicDomain"] is public
    assert entry.get("licence") == (None if public else licence)


def test_a_photograph_with_no_licence_or_credit_is_left_out():
    assert assembly.photo_entry({"url": "u", "credit": "Kari", "licence": ""}) is None
    assert assembly.photo_entry({"url": "u", "credit": "", "licence": "CC0"}) is None


# MARK: - Records, end to end on a fixture


def _feature(naturvern_id, navn, offisielt, verneform, kommune, area_m2, ring, **extra):
    return {
        "type": "Feature",
        "geometry": {"type": "Polygon", "coordinates": [[*ring, ring[0]]]},
        "properties": {
            "naturvernId": naturvern_id, "navn": navn, "offisieltNavn": offisielt,
            "verneform": verneform, "kommune": kommune, "SHAPE.STArea()": area_m2,
            "forvaltningsmyndighet": "Nasjonalparkstyret", "vernedato": 1415923200000,
            "foerstegangVernet": None,
            "faktaark": f"https://faktaark.naturbase.no/?id={naturvern_id}", **extra,
        },
    }


def _box_ring(west, south, size):
    return [[west, south], [west + size, south], [west + size, south + size], [west, south + size]]


@pytest.fixture
def norway(tmp_path, monkeypatch):
    """A raw store and content folder with one park, one landscape and two reserves."""
    raw = tmp_path / "raw" / "2026-11-16"
    vern = raw / fetching.NATURVERN
    vern.mkdir(parents=True)

    def collection(*features):
        return json.dumps({"type": "FeatureCollection", "features": list(features)})

    (vern / "national-parks.geojson").write_text(collection(_feature(
        "VV00001869", "Jotunheimen", "Jotunheimen nasjonalpark", "Nasjonalpark",
        "Lom (3434),Luster (4644)", 1.15e9, _box_ring(8.0, 61.4, 0.5),
    )))
    (vern / "landscapes.geojson").write_text(collection(_feature(
        "VV00000100", "Dividalen", "Dividalen landskapsvernområde", "Landskapsvernomraade",
        "Målselv (5524)", 2.0e8, _box_ring(19.0, 68.8, 0.2), foerstegangVernet=-252460800000,
    )))
    (vern / "reserves.geojson").write_text(collection(
        _feature("VV00000200", "Fokstumyra", "Fokstumyra naturreservat", "Naturreservat",
                 "Dovre (3431)", 1.8e7, _box_ring(9.25, 62.1, 0.08)),
        _feature("VV00000300", "Liten", "Liten naturreservat", "Naturreservat",
                 "Dovre (3431)", 6.0e6, _box_ring(9.4, 62.2, 0.04)),
    ))
    (vern / "counts.json").write_text(json.dumps({"reserves": 2752}))

    content_dir = tmp_path / "content" / "countries" / "no"
    (content_dir / "guides").mkdir(parents=True)
    (content_dir / "national-parks.json").write_text(json.dumps({"parks": [{
        "id": "no-np-jotunheimen", "name": "Jotunheimen", "naturvernId": "VV00001869",
        "svalbard": False, "reachedBy": "  Boat from Gjendesheim  ",
    }]}))
    (content_dir / "guides" / "no-np-jotunheimen.json").write_text(json.dumps({
        "placeID": "no-np-jotunheimen",
        "summary": "The roof of Norway.",
        "facts": {"establishedYear": 1980, "areaHectares": 115100,
                  "bestSeasons": ["summer"], "suggestedTime": "Three to five days"},
        "story": ["Old, hard rock."],
        "howItWorks": ["The right to roam applies."],
        "sights": [
            {"name": "Besseggen", "note": "A ridge.", "location": [61.501, 8.761]},
            {"name": "Memurubu", "note": "A view.", "location": [61.507, 8.783],
             "kind": "viewpoint"},
            {"name": "Norsk Fjellmuseum", "note": "A museum.", "location": [61.837, 8.568],
             "kind": "visitorCentre"},
        ],
        "planYourVisit": {"entrances": ["Gjendesheim"], "camping": [],
                          "seasonalClosureMonths": [11, 12, 1, 13]},
        "fees": [{"title": "Boat", "cost": "NOK 300", "amount": 300, "currencyCode": "nok"}],
        "themes": ["theme-mountains", "theme-not-a-theme"],
        "photos": [],
        "sources": [{"title": "Jotunheimen nasjonalpark — Norges nasjonalparker",
                     "url": "https://www.norgesnasjonalparker.no/nasjonalparker/jotunheimen/"}],
    }))

    monkeypatch.setattr(config, "RAW_DIR", tmp_path / "raw")
    monkeypatch.setattr(config, "CONTENT_DIR", tmp_path / "content")
    monkeypatch.setattr(content, "DIRECTORY", content_dir)
    monkeypatch.setattr(content, "GUIDES_DIR", content_dir / "guides")
    content.parks.cache_clear()
    yield tmp_path
    content.parks.cache_clear()


def test_a_build_on_the_fixture_gives_records_the_app_decodes(norway):
    images = norway / "images"
    images.mkdir()
    share = assembly.assemble(BuildContext(online=False, images_dir=images))
    places = {place["id"]: place for place in share.places}

    park = places["no-np-jotunheimen"]
    assert park["kind"] == "nationalPark" and park["designation"] == "National Park"
    assert park["agency"] == "environmentAgencyNorway" and park["country"] == "NO"
    assert park["subdivisions"][0] in ("NO-34", "NO-46") and len(park["subdivisions"]) == 2
    assert park["passportRegion"] in ("easternNorway", "westernNorway")
    assert park["timeZoneID"] == "Europe/Oslo"
    assert park["localNames"] == [{"language": "nb", "text": "Jotunheimen nasjonalpark"}]
    assert park["facts"] == {"establishedYear": 1980, "areaHectares": 115100,
                             "bestSeasons": ["summer"], "suggestedTime": "Three to five days"}
    assert park["summarySource"] == "Unigrids" and park["themes"] == ["theme-mountains"]
    assert park["officialURL"].startswith("https://www.norgesnasjonalparker.no/")
    assert set(park["centre"]) == {"latitude", "longitude"} and "extent" in park
    assert park["reachedBy"] == "Boat from Gjendesheim"

    landscape = places["no-lvo-dividalen"]
    assert landscape["kind"] == "protectedLandscape"
    assert landscape["designation"] == "Protected Landscape" and landscape["name"] == "Dividalen"
    assert landscape["subdivisions"] == ["NO-55"]
    assert landscape["passportRegion"] == "northernNorway"
    assert landscape["facts"] == {"establishedYear": 1962, "areaHectares": 20000}
    assert "summary" not in landscape

    # Ten square kilometres is the threshold: Fokstumyra is carried, the small one is not.
    assert "no-nr-fokstumyra" in places and "no-nr-liten" not in places
    assert set(places) == set(share.boundaries)
    assert share.expects_summary == {"no-np-jotunheimen"}

    guide = share.guides["no-np-jotunheimen"]
    assert guide["howItWorks"] == ["The right to roam applies."]
    assert guide["planYourVisit"] == {"entrances": ["Gjendesheim"],
                                      "seasonalClosureMonths": [1, 11, 12]}
    assert guide["fees"] == [{"title": "Boat", "cost": "NOK 300", "amount": 300,
                              "currencyCode": "NOK"}]
    pois = {poi["name"]: poi for poi in share.pois}
    assert pois["Besseggen"]["rank"] == 1 and pois["Memurubu"]["rank"] == 2
    assert pois["Norsk Fjellmuseum"]["kind"] == "visitorCentre"
    assert pois["Norsk Fjellmuseum"]["rank"] == 0
    assert pois["Besseggen"]["id"] == "poi-no-jotunheimen-besseggen"
    assert set(guide["sightNotes"]) == {pois["Besseggen"]["id"], pois["Memurubu"]["id"]}
    # Identifiers are resolved through the registries, which the frame saves.
    assert {registry.path.name for registry in share.registries} == {
        "places.json", "pois.json", "trails.json",
    }
    # No raw trails or elevation tiles in the fixture, and offline: none invented.
    assert share.trails == [] and "highestElevationMetres" not in park["facts"]
    assert share.registries[0].owner("no-lvo-dividalen") == "naturvern:VV00000100"


# MARK: - The package


def test_norway_keeps_the_country_contract():
    norway = countries.load("no")
    assert norway.CODE == "no" and norway.NAME == "Norway"
    assert "no" in countries.KNOWN and countries.DEFAULT == ("us",)
    places = [
        {"kind": "nationalPark", "summary": "…"}, {"kind": "protectedLandscape"},
        {"kind": "natureReserve"}, {"kind": "natureReserve"},
    ]
    note = norway.manifest_note(places)
    assert note.startswith("Norway: all 1 national parks with a guide, 1 landscape protection")
    assert "2 nature reserves of 10 km² or more" in note
    places.append({"kind": "nationalPark"})
    assert norway.manifest_note(places).startswith(
        "Norway: all 2 national parks, 1 with a written guide so far,"
    )


def test_photo_urls_are_stable_per_file():
    url = fetching.photo_url("Besseggen above Gjende.jpg")
    assert url == (
        "https://commons.wikimedia.org/wiki/Special:FilePath/Besseggen_above_Gjende.jpg"
        "?width=1920"
    )
    assert content.commons_name("File:Besseggen_above_Gjende.jpg") == "Besseggen above Gjende.jpg"


def test_park_pages_come_from_the_guide_or_the_listing(monkeypatch):
    monkeypatch.setattr(content, "first_source_url", lambda place_id: None)
    listing = {"listCards": [
        {"title": "Rondane nasjonalpark", "links": [{"url": "/nasjonalparker/rondane/"}]},
        {"title": "Nasjonalparkene på Svalbard", "links": [{"url": "/nasjonalparker/svalbard/"}]},
    ]}
    pages = fetching.park_pages(listing, {})
    assert pages["no-np-rondane"].endswith("/nasjonalparker/rondane/")
    assert pages["no-np-forlandet"].endswith("/nasjonalparker/svalbard/")


def test_pdf_links_are_found_in_a_page_and_made_absolute():
    page = {"body": [{"xhtmlString": '<p><a href="/globalassets/kart/rondane.pdf">Kart</a></p>'}],
            "linkCollection": [{"link": {"text": "Brosjyre",
                                         "url": "https://www.miljodirektoratet.no/M925.pdf"}}]}
    links = fetching.pdf_links(page)
    kart = "https://www.norgesnasjonalparker.no/globalassets/kart/rondane.pdf"
    assert {"title": "Kart", "url": kart} in links
    assert {"title": "Brosjyre", "url": "https://www.miljodirektoratet.no/M925.pdf"} in links


def test_a_generic_link_text_gives_way_to_the_file_name():
    link = {"title": "Les mer her",
            "url": "https://www.sysselmesteren.no/a/brosjyre-verneomraadene-svalbard.pdf"}
    assert fetching.document_title(link) == "Brosjyre verneomraadene svalbard"
    assert fetching.document_title({"title": "Kart over Rondane", "url": "x.pdf"}) == (
        "Kart over Rondane"
    )


def test_overpass_is_asked_by_region_with_no_stations_on_svalbard(tmp_path):
    mainland = fetching.region_query((61.0, 4.4, 64.5, 14.5), stations=True)
    assert 'tourism"~"^(alpine_hut|wilderness_hut)$"](61.00000,4.40000,64.50000,14.50000)' in (
        mainland
    )
    assert '"railway"~"^(station|halt)$"' in mainland and "stop_area" in mainland
    assert "railway" not in fetching.region_query(fetching.SVALBARD_REGION, stations=False)
    jobs = [name for name, _, _ in fetching.osm_jobs(tmp_path, refresh=False)]
    assert jobs == [
        "rail-routes-south", "rail-routes-middle", "rail-routes-north",
        "region-south", "region-middle", "region-north", "region-svalbard",
    ]


@pytest.mark.parametrize(
    ("artist", "credit"),
    [
        ('<a href="//commons.wikimedia.org/wiki/User:Koda6029">Koda6029</a>',
         "Koda6029, via Wikimedia Commons"),
        ("No machine-readable author provided. Crown of Lenten rose assumed (based on "
         "copyright claims).", "Crown of Lenten rose, via Wikimedia Commons"),
        ("No machine-readable author provided. Benjaminb~commonswiki assumed (based on "
         "copyright claims).", "Benjaminb, via Wikimedia Commons"),
        # No one to name: credited to its source, never to an invented photographer.
        (None, "Wikimedia Commons"),
    ],
)
def test_a_commons_credit_names_the_author_commons_settled_on(artist, credit):
    from unigrids_pipeline.countries.common import commons_credit

    assert commons_credit(artist) == credit


@pytest.mark.parametrize(
    ("record", "credit"),
    [
        # Commons' Credit field, where it names someone.
        ({"artist": "", "credit": "Photo: Statens vegvesen", "licence": "CC BY 4.0"},
         "Photo: Statens vegvesen, via Wikimedia Commons"),
        # Its boilerplate is a source, not an author; the uploader is next.
        ({"artist": None,
          "credit": "No machine-readable source provided. Own work assumed (based on "
                    "copyright claims).",
          "uploader": "Jojo~commonswiki", "licence": "CC BY-SA 3.0"},
         "Jojo, via Wikimedia Commons"),
        ({"artist": None, "credit": "<span>Own work</span>", "uploader": "Koda6029",
          "licence": "CC BY-SA 3.0"}, "Koda6029, via Wikimedia Commons"),
        # No author anywhere: credited to its source, never to an invented photographer.
        ({"artist": None, "credit": "Own work", "licence": "CC BY-SA 3.0"},
         "Wikimedia Commons"),
        ({"artist": None, "credit": "", "licence": "Public domain"}, "Wikimedia Commons"),
    ],
)
def test_a_commons_credit_falls_back_to_credit_then_uploader(record, credit):
    from unigrids_pipeline.countries.common import commons_record_credit

    assert commons_record_credit(record) == credit
