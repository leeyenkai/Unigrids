"""Reading OpenStreetMap out of a Geofabrik extract in Overpass JSON's shapes.

The fixture is a tiny ``.osm.pbf`` written here with pyosmium: a park box with huts, a
hiking route, named footpaths, and a railway whose big station is not a member of its
route but of the stop area. What comes out must be what the Overpass queries returned,
shape for shape, so the parsers and the keys they make do not change.
"""

from __future__ import annotations

import json
from pathlib import Path

import osmium
import pytest

from unigrids_pipeline import config, outline
from unigrids_pipeline.countries.abroad import trails
from unigrids_pipeline.countries.jp import assembly
from unigrids_pipeline.sources import osm_pbf

PARK_BOX = (35.0, 138.0, 35.2, 138.2)
STATION_BOX = (34.5, 137.5, 35.7, 138.7)
RAIL_BOX = (34.0, 137.0, 36.0, 139.0)
PARK_SQUARE: list[outline.Polygon] = [
    [[(138.0, 35.0), (138.2, 35.0), (138.2, 35.2), (138.0, 35.2)]]
]

# id: (lat, lon, tags)
NODES: dict[int, tuple[float, float, dict[str, str]]] = {
    1: (35.1, 138.1, {"tourism": "alpine_hut", "name": "山小屋", "name:en": "Yama Hut"}),
    2: (35.5, 138.5, {"tourism": "alpine_hut", "name": "Outside Hut"}),
    10: (35.05, 138.05, {}), 11: (35.05, 138.06, {}),
    12: (35.06, 138.06, {}), 13: (35.06, 138.05, {}),
    20: (35.10, 138.10, {}), 21: (35.11, 138.10, {}), 22: (35.12, 138.10, {}),
    30: (35.150, 138.150, {}), 31: (35.151, 138.150, {}),
    32: (35.152, 138.150, {}), 33: (35.153, 138.150, {}),
    34: (35.5, 138.5, {}), 35: (35.51, 138.5, {}),
    # A footpath whose two ends lie outside the box and whose one segment crosses it.
    36: (34.9, 138.1, {}), 37: (35.3, 138.1, {}),
    40: (35.40, 138.40, {}), 41: (35.45, 138.45, {}),
    50: (35.40, 138.40, {"public_transport": "stop_position", "railway": "stop",
                         "train": "yes", "name": "東京"}),
    60: (35.401, 138.401, {"railway": "station", "name": "東京", "name:en": "Tokyo"}),
    61: (35.402, 138.399, {"railway": "station", "name": "東京地下",
                           "station": "subway"}),
    62: (35.6, 138.6, {"railway": "halt", "name": "Faraway"}),
}
WAYS: dict[int, tuple[list[int], dict[str, str]]] = {
    100: ([10, 11, 12, 13, 10], {"tourism": "wilderness_hut", "name": "避難小屋"}),
    200: ([20, 21], {"highway": "path"}),
    201: ([21, 22], {"highway": "path"}),
    300: ([30, 31], {"highway": "footway", "name": "遊歩道"}),
    301: ([32, 33], {"highway": "footway", "name": "遊歩道"}),
    302: ([30, 33], {"highway": "footway"}),
    303: ([34, 35], {"highway": "path", "name": "Far Path"}),
    304: ([36, 37], {"highway": "path", "name": "Crossing Path"}),
    400: ([40, 41], {"railway": "rail"}),
}
RELATIONS: dict[int, tuple[list[tuple[str, int, str]], dict[str, str]]] = {
    1000: ([("w", 200, ""), ("w", 201, "")],
           {"type": "route", "route": "hiking", "name": "縦走路", "name:en": "Ridge Route"}),
    2000: ([("n", 50, "stop"), ("w", 400, "")],
           {"type": "route", "route": "train", "name": "のぞみ (東京→新大阪)"}),
    2100: ([("r", 2000, "")],
           {"type": "route_master", "route_master": "train", "name": "東海道新幹線",
            "name:en": "Tokaido Shinkansen"}),
    2200: ([("n", 50, "stop"), ("n", 60, "")],
           {"type": "public_transport", "public_transport": "stop_area", "name": "東京駅"}),
}


@pytest.fixture(scope="module")
def extract(tmp_path_factory: pytest.TempPathFactory) -> Path:
    path = tmp_path_factory.mktemp("pbf") / "fixture.osm.pbf"
    writer = osmium.SimpleWriter(str(path))
    try:
        for node_id, (lat, lon, tags) in NODES.items():
            writer.add_node(osmium.osm.mutable.Node(id=node_id, location=(lon, lat), tags=tags))
        for way_id, (refs, tags) in WAYS.items():
            writer.add_way(osmium.osm.mutable.Way(id=way_id, nodes=refs, tags=tags))
        for relation_id, (members, tags) in RELATIONS.items():
            writer.add_relation(
                osmium.osm.mutable.Relation(id=relation_id, members=members, tags=tags)
            )
    finally:
        writer.close()
    return path


@pytest.fixture(scope="module")
def selected(extract: Path) -> dict[str, list[dict]]:
    return osm_pbf.select(extract, [
        osm_pbf.Request(name="park", huts=PARK_BOX, stations=STATION_BOX),
        osm_pbf.Request(name="trails", trails=PARK_BOX),
        osm_pbf.Request(name="rail", rail=RAIL_BOX),
    ])


def geometry(*node_ids: int) -> list[dict[str, float]]:
    return [{"lat": NODES[n][0], "lon": NODES[n][1]} for n in node_ids]


def bounds(*node_ids: int) -> dict[str, float]:
    lats = [NODES[n][0] for n in node_ids]
    lons = [NODES[n][1] for n in node_ids]
    return {"minlat": min(lats), "minlon": min(lons), "maxlat": max(lats), "maxlon": max(lons)}


def test_huts_and_stations_come_out_as_park_query_answered(selected):
    assert selected["park"] == [
        {"type": "node", "id": 1, "lat": 35.1, "lon": 138.1, "tags": NODES[1][2]},
        {"type": "way", "id": 100, "center": {"lat": 35.055, "lon": 138.055},
         "tags": WAYS[100][1]},
        {"type": "node", "id": 60, "lat": 35.401, "lon": 138.401, "tags": NODES[60][2]},
        {"type": "node", "id": 61, "lat": 35.402, "lon": 138.399, "tags": NODES[61][2]},
        {"type": "node", "id": 62, "lat": 35.6, "lon": 138.6, "tags": NODES[62][2]},
    ]


def test_trails_come_out_whole_in_out_geom_shape(selected):
    by_key = {(e["type"], e["id"]): e for e in selected["trails"]}
    # Named path and footway ways touching the box; unnamed and far ones are not asked for.
    assert sorted(by_key) == [
        ("relation", 1000), ("way", 300), ("way", 301), ("way", 304),
    ]
    assert by_key[("way", 300)] == {
        "type": "way", "id": 300, "bounds": bounds(30, 31), "nodes": [30, 31],
        "geometry": geometry(30, 31), "tags": WAYS[300][1],
    }
    # Unclipped: both ends lie outside the box.
    assert by_key[("way", 304)]["geometry"] == geometry(36, 37)
    assert by_key[("relation", 1000)] == {
        "type": "relation", "id": 1000, "bounds": bounds(20, 21, 22),
        "members": [
            {"type": "way", "ref": 200, "role": "", "geometry": geometry(20, 21)},
            {"type": "way", "ref": 201, "role": "", "geometry": geometry(21, 22)},
        ],
        "tags": RELATIONS[1000][1],
    }


def test_the_trail_parser_makes_the_same_keys_from_the_extract(selected):
    park = {"id": "jp-np-testsangaku", "name": "Testsangaku"}
    routes = trails.osm_routes("jp", park, {"elements": selected["trails"]}, PARK_SQUARE)
    keys = {route.key: route.name for route in routes}
    assert keys["osm:relation/1000"] == "Ridge Route"
    # The two 遊歩道 footways lie together: one trail, keyed on the lower id.
    assert keys["osm:way/300"] == "遊歩道"
    assert "osm:way/301" not in keys


def test_rail_holds_routes_masters_track_stops_and_the_stop_areas_station(selected):
    rail = selected["rail"]
    assert rail[0] == {
        "type": "relation", "id": 2000,
        "members": [{"type": "node", "ref": 50, "role": "stop"},
                    {"type": "way", "ref": 400, "role": ""}],
        "tags": RELATIONS[2000][1],
    }
    assert rail[1]["id"] == 2100 and rail[1]["tags"]["type"] == "route_master"
    assert rail[2] == {
        "type": "way", "id": 400, "bounds": bounds(40, 41), "nodes": [40, 41],
        "geometry": geometry(40, 41), "tags": {"railway": "rail"},
    }
    nodes = {e["id"]: e for e in rail if e["type"] == "node"}
    # The stop position the route lists, the station of its stop area, and a station
    # within 300 m of the stop; not the halt far away.
    assert sorted(nodes) == [50, 60, 61]
    assert nodes[50]["tags"]["railway"] == "stop"


def test_the_stop_areas_station_is_found_and_named_by_its_route_master(selected):
    network = assembly.RailNetwork({(e["type"], e["id"]): e for e in selected["rail"]})
    stations = {e["id"]: e for e in network.member_stations()}
    assert 60 in stations
    tokyo = network.station(stations[60])
    assert tokyo is not None
    assert tokyo["name"] == "Tokyo"
    assert tokyo["lines"] == ["Tokaido Shinkansen"]
    assert [line["name"] for line in network.lines()] == ["Tokaido Shinkansen"]


def test_hut_keys_are_read_from_extract_elements_as_from_overpass(selected):
    keys = {
        f"osm:{e['type']}/{e['id']}" for e in selected["park"]
        if (e.get("tags") or {}).get("tourism") in ("alpine_hut", "wilderness_hut")
    }
    assert keys == {"osm:node/1", "osm:way/100"}
    assert all(assembly._osm_point(e) for e in selected["park"])


def test_extract_trail_files_land_where_the_build_reads_them(extract, monkeypatch, tmp_path):
    monkeypatch.setattr(config, "RAW_DIR", tmp_path / "raw")
    park = {"id": "jp-np-testsangaku", "name": "Testsangaku"}
    paths = trails.fetch_osm_extract("jp", [(park, PARK_SQUARE)], "2030-01-01", extract)
    assert [path.name for path in paths] == ["jp-np-testsangaku.json"]
    payload = trails._read_osm("jp", park["id"])
    assert payload is not None
    assert {(e["type"], e["id"]) for e in payload["elements"]} >= {
        ("relation", 1000), ("way", 300)
    }
    record = json.loads((paths[0].parent / "source.json").read_text())
    assert record["files"][0]["path"] == "jp-np-testsangaku.json"


@pytest.mark.parametrize(
    ("segment", "expected"),
    [
        (((34.9, 138.1), (35.3, 138.1)), True),   # straight through
        (((34.9, 137.9), (35.3, 138.3)), True),   # diagonally through
        (((34.9, 137.9), (34.95, 138.3)), False),  # passes south of it
    ],
)
def test_a_segment_crossing_the_box_touches_it(segment, expected):
    assert osm_pbf._line_touches(list(segment), PARK_BOX) is expected


def test_japans_fetch_writes_the_files_the_overpass_queries_left(extract, monkeypatch, tmp_path):
    from unigrids_pipeline.countries.jp import fetching

    monkeypatch.setattr(config, "RAW_DIR", tmp_path / "raw")
    park = {"id": "jp-np-testsangaku", "name": "Testsangaku"}
    fetching.fetch_osm_extract(
        "2030-01-01", [park], {park["id"]: PARK_SQUARE}, [(park, PARK_SQUARE)],
        refresh=False, extract=extract,
    )
    root = tmp_path / "raw" / "2030-01-01"
    assert sorted(p.stem for p in (root / "jp-osm" / "rail").glob("*.json")) == sorted(
        fetching.RAIL_REGIONS
    )
    kanto = json.loads((root / "jp-osm" / "rail" / "kanto.json").read_text())
    assert {e["id"] for e in kanto["elements"] if e["type"] == "node"} == {50, 60, 61}
    raw = assembly._Raw(root / "jp-biodic")
    fetched = raw.park_osm(park["id"]) or []
    assert {e["id"] for e in fetched if "tourism" in (e.get("tags") or {})} == {1, 100}
    assert {e["id"] for e in fetched if "railway" in (e.get("tags") or {})} == {60, 61, 62}
    assert (root / "jp-osm-trails" / "jp-np-testsangaku.json").exists()


def test_a_box_is_rounded_as_the_overpass_query_prints_it():
    # A way whose top edge is 35.50786 lies in the query's box "35.50786,…" though not in
    # the unrounded 35.5078638 the box was computed as.
    box = osm_pbf.rounded((35.5078638, 134.1393015, 35.7605396, 135.0476831), 5)
    assert box == (35.50786, 134.1393, 35.76054, 135.04768)
    assert osm_pbf._line_touches([(35.5078543, 134.1772579), (35.50786, 134.1776511)], box)
