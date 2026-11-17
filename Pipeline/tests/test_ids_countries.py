"""Identifiers for the countries added after the US.

Two promises are pinned here: the US's identifiers do not move (``slug`` is untouched,
and nothing already shipped looks like another country's), and a name abroad never turns
into an empty or truncated identifier.
"""

from __future__ import annotations

import json

import pytest

from unigrids_pipeline import config, ids


def test_slug_is_unchanged_for_the_us():
    """``slug`` still deletes what it cannot fold. That is why the countries after the US
    have their own path, and why this one must not be "fixed": US identifiers built with
    it are in users' logs."""
    assert ids.slug("Færder") == "frder"
    assert ids.slug("知床") == ""
    assert ids.slug("Haleakalā") == "haleakala"


@pytest.mark.parametrize(
    ("name", "expected"),
    [
        ("Færder", "faerder"),
        ("Øvre Pasvik", "ovre-pasvik"),
        ("Ånderdalen", "anderdalen"),
        ("ÆØÅ æøå", "aeoa-aeoa"),
        ("đ ŋ ŧ č š ž", "d-n-t-c-s-z"),
        ("Đ Ŋ Ŧ Č Š Ž", "d-n-t-c-s-z"),
        ("Láhku", "lahku"),
        ("Chūbu-Sangaku", "chubu-sangaku"),
        ("Jōshin'etsu Kōgen", "joshinetsu-kogen"),
        ("Fuji・Hakone・Izu", "fuji-hakone-izu"),
        ("Ｆｕｊｉ", "fuji"),
        ("Wrangell–St. Elias", "wrangell-st-elias"),
    ],
)
def test_romanised_slug_keeps_every_letter(name, expected):
    assert ids.romanised_slug(name) == expected


@pytest.mark.parametrize("name", ["知床", "シレトコ", "Shiretoko 知床", "ーー"])
def test_a_name_with_no_latin_form_is_refused_not_truncated(name):
    with pytest.raises(ids.UnromanisedNameError):
        ids.romanised_slug(name)


@pytest.mark.parametrize("name", ["", "   ", "—", "''", "・"])
def test_a_name_with_nothing_to_slug_is_refused(name):
    with pytest.raises(ids.UnromanisedNameError):
        ids.romanised_slug(name)


def test_place_namespaces():
    assert ids.country_place_id("jp", "np", "Shiretoko") == "jp-np-shiretoko"
    assert ids.country_place_id("jp", "qnp", "Abashiri") == "jp-qnp-abashiri"
    assert ids.country_place_id("no", "np", "Færder") == "no-np-faerder"
    assert ids.country_place_id("no", "lvo", "Øvre Pasvik") == "no-lvo-ovre-pasvik"
    assert ids.country_place_id("no", "nr", "Ånderdalen") == "no-nr-anderdalen"


@pytest.mark.parametrize(("country", "tier"), [("jp", "lvo"), ("no", "qnp"), ("us", "np")])
def test_a_namespace_a_country_does_not_have_is_refused(country, tier):
    with pytest.raises(ValueError):
        ids.country_place_id(country, tier, "Anything")


def test_points_of_interest_abroad_are_pinned_to_their_source_key(tmp_path):
    registry = ids.Registry(tmp_path / "pois.json")
    first = ids.country_poi_id(registry, "jp", "chubu-sangaku", "osm:node/1", "Yarigatake Sansō")
    assert first == "poi-jp-chubu-sangaku-yarigatake-sanso"
    # Renamed at the source: same key, same identifier.
    renamed = ids.country_poi_id(registry, "jp", "chubu-sangaku", "osm:node/1", "Yari Hut")
    assert renamed == first
    # Another record of the same name is qualified, not merged with the first.
    second = ids.country_poi_id(registry, "jp", "chubu-sangaku", "osm:node/2", "Yarigatake Sansō")
    assert second == "poi-jp-chubu-sangaku-yarigatake-sanso-2"


def test_trails_abroad_are_pinned_to_their_source_key(tmp_path):
    registry = ids.Registry(tmp_path / "trails.json")
    trail = ids.country_trail_id(registry, "no", "jotunheimen", "turrutebasen:1234", "Besseggen")
    assert trail == "trail-no-jotunheimen-besseggen"


@pytest.mark.parametrize("name", [None, "", "槍ヶ岳山荘"])
def test_a_record_with_no_latin_name_is_named_by_its_source_key(tmp_path, name):
    registry = ids.Registry(tmp_path / "pois.json")
    poi = ids.country_poi_id(registry, "jp", "chubu-sangaku", "osm:node/123", name)
    assert poi == "poi-jp-chubu-sangaku-osm-node-123"


@pytest.mark.parametrize("key", ["123", ":123", "osm:"])
def test_a_registry_key_names_its_source(tmp_path, key):
    registry = ids.Registry(tmp_path / "pois.json")
    with pytest.raises(ValueError):
        ids.country_poi_id(registry, "jp", "chubu-sangaku", key, "A hut")


def test_registries_abroad_live_in_a_folder_per_country():
    registry = ids.country_registry("no", "trails")
    assert registry.path == config.CONTENT_DIR / "ids" / "no" / "trails.json"
    with pytest.raises(ValueError):
        ids.country_registry("us", "pois")
    with pytest.raises(ValueError):
        ids.country_registry("jp", "sights")


def test_country_is_read_off_an_identifier():
    assert ids.country_of("jp-np-shiretoko") == "jp"
    assert ids.country_of("no-lvo-ovre-pasvik") == "no"
    assert ids.country_of("poi-jp-chubu-sangaku-yarigatake-sanso") == "jp"
    assert ids.country_of("trail-no-jotunheimen-besseggen") == "no"
    assert ids.country_of("np-zion") == "us"
    assert ids.country_of("poi-zion-angels-landing") == "us"
    assert ids.country_of("trail-zion-the-narrows") == "us"


def test_every_bundled_identifier_names_its_own_country():
    """An identifier's prefix is the country the app files a visit under once its place
    has left the dataset, so it must agree with the country the record says it is in: a
    US place never reads as Japanese or Norwegian, and a place abroad never as American.
    A point of interest or trail goes by the place it belongs to."""
    from unigrids_pipeline import reference_build

    places = json.loads((reference_build.OUT / "places.json").read_text())
    assert len(places) > 5000
    country = {place["id"]: place.get("country", "US").lower() for place in places}
    wrong = [pid for pid, code in country.items() if ids.country_of(pid) != code]
    for name in ("pois", "trails"):
        rows = json.loads((reference_build.OUT / f"{name}.json").read_text())
        wrong.extend(
            row["id"] for row in rows
            if row.get("placeID") in country
            and ids.country_of(row["id"]) != country[row["placeID"]]
        )
    assert wrong == []
    # Every US identifier still has no country prefix at all.
    prefixes = tuple(
        f"{kind}{code}-"
        for code in ids.PLACE_NAMESPACES
        if code != "us"
        for kind in ("", "poi-", "trail-")
    )
    american = [pid for pid, code in country.items() if code == "us"]
    assert [pid for pid in american if pid.startswith(prefixes)] == []
