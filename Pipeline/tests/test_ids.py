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
