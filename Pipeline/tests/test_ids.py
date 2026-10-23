"""The identifier rules are the pipeline's contract with the user's log.

An ID that changes between runs orphans someone's visit (``AGENTS.md`` §4), so these
tests pin the properties that keep that from happening.
"""

from unigrids_pipeline import ids


def test_slug_is_lowercase_and_hyphenated():
    assert ids.slug("Great Smoky Mountains") == "great-smoky-mountains"
    assert ids.slug("Wrangell–St. Elias") == "wrangell-st-elias"


def test_diacritics_fold_so_a_spelling_fix_does_not_change_an_id():
    assert ids.slug("Haleakalā") == ids.slug("Haleakala") == "haleakala"
    assert ids.slug("Hawaiʻi Volcanoes") == "hawaii-volcanoes"


def test_slug_is_stable_under_punctuation_and_spacing():
    assert ids.slug("  Black Canyon of the Gunnison  ") == "black-canyon-of-the-gunnison"
    assert ids.slug("Clingmans Dome / Kuwohi") == "clingmans-dome-kuwohi"


def test_prefixes_match_the_bundled_seed():
    assert ids.place_id("np", "Zion") == "np-zion"
    assert ids.poi_id("zion", "Angels Landing") == "poi-zion-angels-landing"
    assert ids.trail_id("zion", "The Narrows") == "trail-zion-the-narrows"
    assert ids.theme_id("Volcanoes") == "theme-volcanoes"


def test_every_seed_park_slug_is_already_a_slug():
    """The bundled seed's IDs must survive a round trip through ``slug``.

    A few seed slugs are deliberate shortenings — ``american-samoa`` for "National Park
    of American Samoa" — so this does not assert they equal ``slug(name)``. It asserts
    the weaker, important thing: no seed ID would change if the pipeline re-slugged it.
    """
    import sys
    from pathlib import Path

    sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "seed"))
    from parks import PARKS

    for park_slug, name, *_ in PARKS:
        assert ids.slug(park_slug) == park_slug, f"{name} -> {park_slug}"


def test_registry_keeps_the_first_answer_for_a_key(tmp_path):
    registry = ids.Registry(tmp_path / "ids.json")
    assert registry.resolve("usfs-forest:COCONINO", "nf-coconino") == "nf-coconino"
    # The source renames the record: the key is the same, so the identifier is too.
    assert registry.resolve("usfs-forest:COCONINO", "nf-coconino-renamed") == "nf-coconino"
    registry.save()
    reopened = ids.Registry(tmp_path / "ids.json")
    assert reopened.resolve("usfs-forest:COCONINO", "anything") == "nf-coconino"
    assert reopened.added == 0


def test_registry_qualifies_a_second_record_rather_than_dropping_it(tmp_path):
    registry = ids.Registry(tmp_path / "ids.json")
    first = registry.resolve("padus-sp:NY:Lake State Park", "sp-lake", qualifier="NY")
    second = registry.resolve("padus-sp:OH:Lake State Park", "sp-lake", qualifier="OH")
    third = registry.resolve("padus-sp:OH:Lake  State Park", "sp-lake", qualifier="OH")
    assert (first, second, third) == ("sp-lake", "sp-lake-oh", "sp-lake-oh-2")
    fourth = registry.resolve("padus-sp:OH:Lake   State Park", "sp-lake", qualifier="OH")
    assert fourth == "sp-lake-oh-3"


def test_registry_refuses_a_file_where_two_keys_share_an_identifier(tmp_path):
    import json

    import pytest

    path = tmp_path / "ids.json"
    path.write_text(json.dumps({"a": "nf-x", "b": "nf-x"}))
    with pytest.raises(ids.IdentifierCollisionError):
        ids.Registry(path)


def test_every_bundled_agency_land_is_in_the_registry():
    """The committed dataset's identifiers are what users' logs hold. Every one that came
    from an agency source must be pinned in the registry, or the next refresh is free to
    hand it to something else."""
    import json

    from unigrids_pipeline import config, reference_build

    places = json.loads((reference_build.OUT / "places.json").read_text())
    registry = ids.Registry(config.CONTENT_DIR / "ids" / "places.json")
    agency_kinds = {
        "nationalForest", "nationalGrassland", "wildlifeRefuge", "naturalLandmark",
        "scenicByway",
    }
    for place in places:
        if place["kind"] in agency_kinds:
            assert registry.owner(place["id"]) is not None, place["id"]
