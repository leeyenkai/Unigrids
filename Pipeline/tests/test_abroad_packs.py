"""The pack steps for a park abroad: which ``--park`` names one, how deep its tiles go,
what it draws as trails, and the credit its manifest carries."""

from __future__ import annotations

from pathlib import Path

from unigrids_pipeline import steps
from unigrids_pipeline.countries.abroad import packs


def test_a_place_id_abroad_is_told_apart_from_an_nps_code():
    assert packs.is_abroad("jp-np-chubusangaku")
    assert packs.is_abroad("no-np-jotunheimen")
    assert not packs.is_abroad("ZION")
    assert not packs.is_abroad("np-zion")
    assert steps._place_id("no-np-jotunheimen") == "no-np-jotunheimen"
    assert steps._place_id("ZION") == "np-zion"


def test_a_national_park_in_any_country_abroad_can_have_a_pack():
    assert set(steps.ABROAD) == set(packs.COUNTRIES)
    for place_id in ("nz-np-tongariro", "au-np-blue-mountains", "ca-np-banff"):
        assert packs.is_abroad(place_id)
        assert steps._is_abroad(place_id)
        assert steps._place_id(place_id) == place_id


def test_a_park_abroad_is_found_in_its_countrys_content_list():
    park = packs.park("no-np-jotunheimen")
    assert park.place_id == "no-np-jotunheimen"
    assert park.slug == "jotunheimen"
    assert park.name == "Jotunheimen National Park"
    assert packs.park("nz-np-tongariro").name == "Tongariro National Park"
    assert packs.park("ca-np-banff").name == "Banff National Park"
    blue_mountains = packs.park("au-np-blue-mountains")
    assert blue_mountains.name == "Blue Mountains National Park"
    assert blue_mountains.slug == "blue-mountains"


def test_a_pack_is_titled_with_the_parks_designation_once():
    assert packs.full_name({"name": "Tongariro"}) == "Tongariro National Park"
    assert packs.full_name({"name": "Kakadu National Park"}) == "Kakadu National Park"
    assert packs.full_name(
        {"name": "Daintree National Park (CYPAL)"}
    ) == "Daintree National Park (CYPAL)"
    assert packs.full_name(
        {"name": "Pacific Rim", "officialName": "Pacific Rim National Park Reserve"}
    ) == "Pacific Rim National Park Reserve"


def test_tiles_abroad_stop_at_zoom_15_whatever_the_area():
    assert packs.deepest_zoom(150.0, 16, by_area=True) == 15
    assert packs.deepest_zoom(150.0, 16, by_area=False) == 15
    assert packs.deepest_zoom(5_000.0, 16, by_area=True) == 15
    assert packs.deepest_zoom(50_000.0, 16, by_area=True) == 13
    assert packs.deepest_zoom(150.0, 14, by_area=False) == 14


def test_the_credit_names_the_trail_sources_the_pack_uses():
    norway = packs.attribution_line("no", [{"source": "kartverket"}], drawn_from=[Path("x")])
    assert norway == (
        "Elevation Copernicus GLO-30 · Roads and water © OpenStreetMap contributors (ODbL) · "
        "Trails Kartverket"
    )
    japan = packs.attribution_line("jp", [{"source": "osm"}], drawn_from=[])
    assert japan.endswith("· Trails OpenStreetMap")
    both = packs.attribution_line("no", [{"source": "osm"}], drawn_from=[Path("x")])
    assert both.endswith("· Trails Kartverket/OpenStreetMap")
    new_zealand = packs.attribution_line("nz", [{"source": "doc"}], drawn_from=[])
    assert new_zealand.endswith("· Trails Department of Conservation/OpenStreetMap")
    canada = packs.attribution_line("ca", [{"source": "parksCanada"}], drawn_from=[])
    assert canada.endswith("· Trails Parks Canada/OpenStreetMap")
    new_south_wales = packs.attribution_line("au", [{"source": "osm"}], drawn_from=[])
    assert new_south_wales.endswith("· Trails OpenStreetMap")


def test_osm_footpaths_are_drawn_but_not_a_towns_sidewalks_or_its_roads():
    def way(highway: str, **tags: str) -> dict:
        return {
            "tags": {"highway": highway, **tags},
            "geometry": [{"lon": 137.6, "lat": 36.3}, {"lon": 137.61, "lat": 36.31}],
        }

    ways = [way("path"), way("footway"), way("steps"), way("footway", footway="sidewalk"),
            way("residential")]
    drawn, sources = packs.trail_features("jp", "jp-np-chubusangaku", ways)
    assert [feature["properties"]["highway"] for feature in drawn] == ["path", "footway", "steps"]
    assert sources == []


def test_a_lake_mapped_as_many_shoreline_ways_fills_as_one_ring():
    north_shore = [{"lon": 8.0, "lat": 61.5}, {"lon": 8.5, "lat": 61.6}, {"lon": 9.0, "lat": 61.5}]
    south_shore = [{"lon": 9.0, "lat": 61.5}, {"lon": 8.5, "lat": 61.4}, {"lon": 8.0, "lat": 61.5}]
    payload = {"elements": [
        {"type": "way", "id": 1, "tags": {"highway": "track"},
         "geometry": [{"lon": 8.0, "lat": 61.0}, {"lon": 8.1, "lat": 61.1}]},
        {"type": "relation", "id": 9, "tags": {"natural": "water", "type": "multipolygon"},
         "members": [
             {"type": "way", "role": "outer", "geometry": north_shore},
             {"type": "way", "role": "outer", "geometry": south_shore},
         ]},
    ]}
    elements = packs.water_as_rings(payload)["elements"]
    assert [element["type"] for element in elements] == ["way", "way"]
    lake = elements[1]
    assert lake["tags"]["natural"] == "water"
    assert lake["geometry"][0] == lake["geometry"][-1]
    assert len(lake["geometry"]) == 5
