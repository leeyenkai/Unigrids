"""The trail catalogue abroad: Turrutebasen's routes and grades, OpenStreetMap's paths,
identifiers through the country registries, and records in the US catalogue's shape.

Everything here is synthetic and offline. The lines run due north or east from a point
inside a square "park", and the elevation is a plane, so lengths and climbs are known.
"""

from __future__ import annotations

import json
import math
from collections import Counter
from pathlib import Path

import pytest

from unigrids_pipeline import config, geo, ids, outline
from unigrids_pipeline.countries.abroad import trails

PARK = {"id": "no-np-testheimen", "name": "Testheimen"}
JP_PARK = {"id": "jp-np-testsangaku", "name": "Testsangaku"}
PARK_SQUARE: list[outline.Polygon] = [[[(8.0, 61.0), (8.5, 61.0), (8.5, 61.5), (8.0, 61.5)]]]


def north(start: tuple[float, float], metres: float, steps: int = 6) -> list[tuple[float, float]]:
    span = math.degrees(metres / geo.meridional_radius_m(start[1]))
    return [(start[0], start[1] + span * index / (steps - 1)) for index in range(steps)]


def east(start: tuple[float, float], metres: float, steps: int = 6) -> list[tuple[float, float]]:
    radius = geo.prime_vertical_radius_m(start[1]) * math.cos(math.radians(start[1]))
    span = math.degrees(metres / radius)
    return [(start[0] + span * index / (steps - 1), start[1]) for index in range(steps)]


def rising(longitude: float, latitude: float) -> float:
    """A plane that climbs 100 m per kilometre northwards."""
    return 500.0 + (latitude - 61.0) * geo.meridional_radius_m(61.0) * math.pi / 180 * 0.1


class PlaneDEM:
    def sample(self, longitude: float, latitude: float) -> float | None:
        return rising(longitude, latitude)


@pytest.fixture
def registry(tmp_path: Path) -> ids.Registry:
    return ids.Registry(tmp_path / "trails.json")


# --- Turrutebasen -----------------------------------------------------------------------

GML = """<?xml version='1.0' encoding='UTF-8'?>
<wfs:FeatureCollection xmlns:wfs="http://www.opengis.net/wfs/2.0"
  xmlns:gml="http://www.opengis.net/gml/3.2"
  xmlns:app="http://skjema.geonorge.no/SOSI/produktspesifikasjon/TurOgFriluftsruter/20171210">
  <wfs:member>
    <app:Fotrute gml:id="fotrute.1">
      <app:identifikasjon><app:Identifikasjon>
        <app:lokalId>aaaa</app:lokalId>
      </app:Identifikasjon></app:identifikasjon>
      <app:senterlinje><gml:LineString srsName="urn:ogc:def:crs:EPSG::4326">
        <gml:posList>61.100000 8.200000 61.105000 8.200000</gml:posList>
      </gml:LineString></app:senterlinje>
      <app:merking>JA</app:merking>
      <app:ruteFølger>ST</app:ruteFølger>
      <app:fotruteInfo>
        <app:FotruteInfo>
          <app:rutenavn>Gjendesheim-Memurubu</app:rutenavn>
          <app:rutenummer>jot31</app:rutenummer>
          <app:vedlikeholdsansvarlig>DNT</app:vedlikeholdsansvarlig>
          <app:gradering>R</app:gradering>
        </app:FotruteInfo>
        <app:FotruteInfo>
          <app:rutenavn>Ukjent</app:rutenavn>
          <app:rutenummer>jot88</app:rutenummer>
          <app:gradering></app:gradering>
        </app:FotruteInfo>
      </app:fotruteInfo>
    </app:Fotrute>
  </wfs:member>
</wfs:FeatureCollection>
"""


def test_the_gml_is_read_longitude_first_with_every_route_on_the_segment():
    features = trails.parse_fotruter(GML.encode())
    assert len(features) == 1
    feature = features[0]
    assert feature["geometry"]["coordinates"] == [[8.2, 61.1], [8.2, 61.105]]
    properties = feature["properties"]
    assert properties["lokalId"] == "aaaa"
    assert properties["marked"] == "JA"
    assert properties["follows"] == "ST"
    assert [route["number"] for route in properties["routes"]] == ["jot31", "jot88"]
    assert properties["routes"][0]["grade"] == "R"


def segment(
    line: list[tuple[float, float]], *routes: dict[str, str], lokal_id: str = "x"
) -> dict:
    return {
        "type": "Feature",
        "properties": {"lokalId": lokal_id, "routes": list(routes)},
        "geometry": {"type": "LineString", "coordinates": [list(point) for point in line]},
    }


def route_info(number: str, name: str, grade: str = "") -> dict[str, str]:
    return {"number": number, "name": name, "grade": grade}


def test_segments_are_joined_by_route_number_and_unnamed_routes_left_out():
    first = north((8.2, 61.1), 600)
    second = north(first[-1], 600)
    features = [
        segment(first, route_info("jot31", "Gjendesheim-Memurubu", "B"),
                route_info("jot88", "Ukjent"), lokal_id="a"),
        segment(second, route_info("jot31", "Gjendesheim-Memurubu", "B"), lokal_id="b"),
    ]
    routes = trails.turrutebasen_routes(PARK, features, PARK_SQUARE)
    assert [route.name for route in routes] == ["Gjendesheim-Memurubu"]
    route = routes[0]
    assert route.key == "turrutebasen:testheimen/jot31"
    assert route.source == "kartverket"
    assert len(route.segments) == 2
    assert route.grade == {
        "system": "norwegianMarking",
        "grade": "B",
        "publisher": "Kartverket (Turrutebasen)",
        "sourceURL": trails.TURRUTEBASEN_DATASET,
    }


def test_a_route_without_a_number_is_keyed_on_its_lowest_segment_id():
    features = [
        segment(north((8.2, 61.1), 400), route_info("", "Stien"), lokal_id="b-2"),
        segment(north((8.2, 61.2), 400), route_info("", "Stien"), lokal_id="a-1"),
    ]
    routes = trails.turrutebasen_routes(PARK, features, PARK_SQUARE)
    assert [route.key for route in routes] == ["turrutebasen:testheimen/a-1"]


def test_segments_outside_the_park_are_not_the_parks():
    features = [
        segment(north((8.2, 61.1), 400), route_info("x1", "Inne"), lokal_id="a"),
        segment(north((9.5, 61.1), 400), route_info("x2", "Ute"), lokal_id="b"),
    ]
    routes = trails.turrutebasen_routes(PARK, features, PARK_SQUARE)
    assert [route.name for route in routes] == ["Inne"]


@pytest.mark.parametrize(
    ("grades", "expected"),
    [
        ({"G": 3}, "G"),
        ({"B": 1}, "B"),
        ({"R": 2}, "R"),
        ({"S": 1}, "S"),
        ({"I": 4}, "I"),  # deliberately ungraded, kept as published
        ({"G": 1, "R": 1}, None),  # segments disagree: no grade rather than a choice
        ({}, None),
        ({"X": 1}, None),
    ],
)
def test_turrutebasen_grades_are_kept_as_published(grades, expected):
    grade = trails.published_grade(Counter(grades))
    if expected is None:
        assert grade is None
    else:
        assert grade["grade"] == expected
        assert grade["system"] == "norwegianMarking"
        assert grade["publisher"] == "Kartverket (Turrutebasen)"


# --- OpenStreetMap ----------------------------------------------------------------------


def way(identifier: int, line: list[tuple[float, float]], **tags: str) -> dict:
    return {
        "type": "way",
        "id": identifier,
        "tags": {"highway": "path", **tags},
        "geometry": [{"lon": lon, "lat": lat} for lon, lat in line],
    }


def relation(identifier: int, members: list[list[tuple[float, float]]], **tags: str) -> dict:
    return {
        "type": "relation",
        "id": identifier,
        "tags": {"type": "route", "route": "hiking", **tags},
        "members": [
            {"type": "way", "ref": index, "role": "",
             "geometry": [{"lon": lon, "lat": lat} for lon, lat in line]}
            for index, line in enumerate(members)
        ],
    }


def test_a_hiking_relation_is_one_trail_and_a_way_of_its_name_is_not_another():
    first = north((8.2, 61.1), 500)
    second = north(first[-1], 500)
    payload = {"elements": [
        relation(77, [first, second], name="Kammen"),
        way(5, first, name="Kammen"),
    ]}
    routes = trails.osm_routes("no", PARK, payload, PARK_SQUARE)
    assert [(route.key, route.name, len(route.segments)) for route in routes] == [
        ("osm:relation/77", "Kammen", 2)
    ]
    assert routes[0].source == "osm"


def test_named_ways_are_joined_by_name_only_where_they_lie_together():
    near_a = north((8.2, 61.1), 400)
    near_b = north(near_a[-1], 400)
    far = north((8.4, 61.4), 400)
    payload = {"elements": [
        way(30, near_b, name="遊歩道"),
        way(20, near_a, name="遊歩道"),
        way(10, far, name="遊歩道"),
        way(40, east((8.3, 61.2), 300), name="遊歩道", footway="sidewalk", highway="footway"),
        way(50, east((8.3, 61.3), 900), name="二番通り1号林道"),
    ]}
    routes = trails.osm_routes("jp", JP_PARK, payload, PARK_SQUARE)
    assert sorted(route.key for route in routes) == ["osm:way/10", "osm:way/20"]
    joined = next(route for route in routes if route.key == "osm:way/20")
    assert len(joined.segments) == 2


def test_japanese_trails_show_english_where_osm_has_it_and_mint_ids_from_latin_names():
    payload = {"elements": [
        relation(1, [north((8.2, 61.1), 400)], name="槍ヶ岳登山道", **{"name:en": "Yari Trail"}),
        relation(2, [north((8.3, 61.1), 400)], name="燕岳登山道"),
    ]}
    routes = {route.key: route for route in trails.osm_routes("jp", JP_PARK, payload, PARK_SQUARE)}
    assert routes["osm:relation/1"].name == "Yari Trail"
    assert routes["osm:relation/1"].latin_name == "Yari Trail"
    assert routes["osm:relation/2"].name == "燕岳登山道"
    assert routes["osm:relation/2"].latin_name is None


# --- identifiers --------------------------------------------------------------------------


def test_identifiers_are_minted_through_the_registry_on_the_source_key(registry):
    first = ids.country_trail_id(
        registry, "no", "testheimen", "turrutebasen:testheimen/jot31", "Gjendesheim-Memurubu"
    )
    assert first == "trail-no-testheimen-gjendesheim-memurubu"
    # Renamed at the source: the identifier stays, because the key does.
    again = ids.country_trail_id(
        registry, "no", "testheimen", "turrutebasen:testheimen/jot31", "Gjendesheim–Memurubu (ny)"
    )
    assert again == first
    # Another route that would slug the same way gets its own.
    other = ids.country_trail_id(
        registry, "no", "testheimen", "turrutebasen:testheimen/jot99", "Gjendesheim-Memurubu"
    )
    assert other == "trail-no-testheimen-gjendesheim-memurubu-2"


def test_a_japanese_name_without_a_latin_form_is_named_by_its_key(registry):
    identifier = ids.country_trail_id(
        registry, "jp", "testsangaku", "osm:relation/2", None
    )
    assert identifier == "trail-jp-testsangaku-osm-relation-2"


# --- measuring and the record ------------------------------------------------------------


def measured(route: trails.Route, registry: ids.Registry, sights=(), anchors=()) -> dict:
    record = trails.trail_record(
        "no", PARK, route, PlaneDEM().sample, list(sights), list(anchors), registry
    )
    assert record is not None
    return record


def test_a_route_is_measured_and_recorded_in_the_us_catalogues_shape(registry):
    line = north((8.2, 61.1), 2000, steps=21)
    route = trails.Route(
        key="turrutebasen:testheimen/jot31",
        name="Bessvatnet  rundt",
        latin_name="Bessvatnet rundt",
        source="kartverket",
        segments=[line],
        grade=trails.published_grade(Counter({"R": 1})),
        names=("Bessvatnet rundt",),
    )
    record = measured(route, registry)
    assert list(record) == [
        "id", "placeID", "name", "lengthMetres", "paths", "gainMetres", "lossMetres",
        "highPointMetres", "lowPointMetres", "profile", "source", "publishedGrade", "features",
    ]
    assert record["id"] == "trail-no-testheimen-bessvatnet-rundt"
    assert record["placeID"] == "no-np-testheimen"
    assert record["name"] == "Bessvatnet rundt"
    assert record["lengthMetres"] == pytest.approx(2000, abs=2)
    # Walked uphill from the lower end: 100 m per kilometre, every metre counted.
    assert record["gainMetres"] == pytest.approx(200, abs=3)
    assert record["lossMetres"] == pytest.approx(0, abs=1)
    assert record["lowPointMetres"] < record["highPointMetres"]
    assert 2 <= len(record["profile"]) <= trails.PROFILE_POINTS
    assert record["profile"][0][0] == 0
    assert record["source"] == "kartverket"
    assert record["publishedGrade"]["grade"] == "R"
    assert record["features"] == ["lake"]
    decoded = outline.decode(record["paths"][0])
    assert decoded[0][1] < decoded[-1][1]  # walked south to north, up the slope


def test_a_route_digitised_downhill_is_walked_uphill(registry):
    line = list(reversed(north((8.2, 61.1), 1500, steps=16)))
    route = trails.Route(key="osm:way/1", name="Opp", latin_name="Opp", source="osm",
                         segments=[line], uses="Hike")
    record = measured(route, registry)
    assert record["gainMetres"] == pytest.approx(150, abs=3)
    assert record["uses"] == "Hike"
    assert "bikesAllowed" not in record


def test_a_closed_line_is_a_loop(registry):
    start = (8.2, 61.2)
    loop = [*east(start, 400), *north(east(start, 400)[-1], 400)[1:]]
    back = [*east(loop[-1], -400)[1:], *north(start, 400)[::-1][:-1], start]
    route = trails.Route(key="osm:way/9", name="Ring", latin_name="Ring", source="osm",
                         segments=[loop + back])
    assert measured(route, registry)["routeType"] == "loop"


def test_sights_within_200_metres_are_listed_in_walking_order(registry):
    line = north((8.2, 61.1), 2000, steps=21)
    near_end = {"id": "poi-b", "kind": "sight", "location": {
        "longitude": line[-3][0] + 0.001, "latitude": line[-3][1]}}
    near_start = {"id": "poi-a", "kind": "sight", "location": {
        "longitude": line[2][0], "latitude": line[2][1]}}
    far = {"id": "poi-c", "kind": "sight", "location": {"longitude": 8.4, "latitude": 61.4}}
    route = trails.Route(key="osm:way/2", name="Dalen", latin_name="Dalen", source="osm",
                         segments=[line])
    record = measured(route, registry, sights=[near_end, far, near_start])
    assert record["sightIDs"] == ["poi-a", "poi-b"]


def test_a_line_under_250_metres_is_not_a_trail(registry):
    route = trails.Route(key="osm:way/3", name="Kort", latin_name="Kort", source="osm",
                         segments=[north((8.2, 61.1), 200)])
    assert trails.trail_record("no", PARK, route, PlaneDEM().sample, [], [], registry) is None


def test_without_elevation_the_length_stands_and_no_climb_is_given(registry):
    route = trails.Route(key="osm:way/4", name="Flat", latin_name="Flat", source="osm",
                         segments=[north((8.2, 61.1), 800)])
    record = trails.trail_record("no", PARK, route, lambda lon, lat: None, [], [], registry)
    assert record is not None
    assert record["lengthMetres"] == pytest.approx(800, abs=2)
    assert "gainMetres" not in record and "profile" not in record


@pytest.mark.parametrize(
    ("names", "expected"),
    [
        (("Vettisfossen",), ["waterfall"]),
        (("Skagastølstind - Turtagrø",), ["summit"]),
        (("Gjendebu-Fossbu",), []),  # a hut called Fossbu is not a waterfall
        (("Bødalsbreen",), ["glacier"]),
        (("槍ヶ岳登山道",), ["summit"]),
        (("富士山",), ["summit"]),
        (("白糸の滝遊歩道",), ["waterfall"]),
        (("尾瀬ヶ原湿原",), ["meadow"]),
        (("Lake Trail", "湖畔道"), ["lake"]),
    ],
)
def test_features_come_from_the_trails_own_name_in_its_own_language(names, expected):
    assert trails.features(names) == expected


# --- the whole park ----------------------------------------------------------------------


def test_build_reads_the_raw_store_and_falls_back_to_osm_only_without_turrutebasen(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, registry: ids.Registry
):
    monkeypatch.setattr(config, "RAW_DIR", tmp_path / "raw")
    day = tmp_path / "raw" / "2026-11-16"
    with_routes = {"id": "no-np-a", "name": "A"}
    without = {"id": "no-np-b", "name": "B"}
    svalbard = {"id": "no-np-c", "name": "C"}
    (day / trails.TURRUTEBASEN).mkdir(parents=True)
    (day / trails.TURRUTEBASEN / "no-np-a.geojson").write_text(json.dumps({"features": [
        segment(north((8.2, 61.1), 1200), route_info("a1", "Ruta"), lokal_id="s"),
    ]}))
    (day / trails.TURRUTEBASEN / "no-np-b.geojson").write_text(json.dumps({"features": []}))
    (day / trails.TURRUTEBASEN / "no-np-c.geojson").write_text(json.dumps({"features": []}))
    (day / "no-osm-trails").mkdir(parents=True)
    (day / "no-osm-trails" / "no-np-a.json").write_text(json.dumps({"elements": [
        relation(5, [north((8.3, 61.1), 900)], name="Skulle ikke med"),
    ]}))
    (day / "no-osm-trails" / "no-np-b.json").write_text(json.dumps({"elements": [
        relation(6, [north((8.3, 61.1), 900)], name="Stien"),
    ]}))
    (day / "no-osm-trails" / "no-np-c.json").write_text(json.dumps({"elements": []}))
    outlines = {park["id"]: PARK_SQUARE for park in (with_routes, without, svalbard)}
    records = trails.build(
        "no", [with_routes, without, svalbard], outlines, {},
        online=False, registry=registry, dem=PlaneDEM(),
    )
    assert [(record["placeID"], record["name"], record["source"]) for record in records] == [
        ("no-np-a", "Ruta", "kartverket"),
        ("no-np-b", "Stien", "osm"),
    ]
    assert records[0]["id"] == "trail-no-a-ruta"
    assert all("gainMetres" in record for record in records)


def test_a_park_kartverket_never_answered_for_is_not_filled_from_osm(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, registry: ids.Registry
):
    monkeypatch.setattr(config, "RAW_DIR", tmp_path / "raw")
    day = tmp_path / "raw" / "2026-11-16" / "no-osm-trails"
    day.mkdir(parents=True)
    (day / "no-np-a.json").write_text(json.dumps({"elements": [
        relation(6, [north((8.3, 61.1), 900)], name="Stien"),
    ]}))
    records = trails.build(
        "no", [{"id": "no-np-a"}], {"no-np-a": PARK_SQUARE}, {},
        online=False, registry=registry, dem=PlaneDEM(),
    )
    assert records == []


def test_a_park_box_is_asked_for_in_tiles_that_cover_it_exactly():
    box = geo.BoundingBox(west=7.0, south=61.0, east=8.2, north=61.6)
    tiles = trails.search_tiles(box)
    assert len(tiles) == 3 * 3
    assert min(tile.south for tile in tiles) == 61.0 and max(tile.north for tile in tiles) == 61.6
    assert min(tile.west for tile in tiles) == 7.0 and max(tile.east for tile in tiles) == 8.2
    assert all(tile.north - tile.south <= 0.25 + 1e-9 for tile in tiles)
    assert all(tile.east - tile.west <= 0.5 + 1e-9 for tile in tiles)


def test_a_segment_with_no_length_does_not_leave_the_trail_unmeasured(registry):
    line = north((8.2, 61.1), 1000, steps=11)
    route = trails.Route(key="osm:way/5", name="Stien", latin_name="Stien", source="osm",
                         segments=[line, [(8.4, 61.3), (8.4, 61.3)]])
    record = measured(route, registry)
    assert record["gainMetres"] == pytest.approx(100, abs=3)


def test_a_box_no_server_answers_whole_is_asked_for_in_quarters_and_merged(
    monkeypatch: pytest.MonkeyPatch,
):
    from unigrids_pipeline.sources import http

    asked: list[str] = []

    def fake_overpass(session, query):
        asked.append(query)
        if query == "61.0-62.0":
            raise http.FetchError("504")
        # Every quarter returns the shared relation and one way of its own.
        return {"elements": [
            {"type": "relation", "id": 1},
            {"type": "way", "id": len(asked)},
        ]}, "https://example.invalid/api/interpreter"

    monkeypatch.setattr(trails, "overpass", fake_overpass)
    box = geo.BoundingBox(west=8.0, south=61.0, east=9.0, north=62.0)
    elements, queries = trails.overpass_box(
        None, box, lambda b: f"{b.south:.1f}-{b.north:.1f}"
    )
    assert len(queries) == 4
    assert sorted((e["type"], e["id"]) for e in elements) == [
        ("relation", 1), ("way", 2), ("way", 3), ("way", 4), ("way", 5),
    ]
