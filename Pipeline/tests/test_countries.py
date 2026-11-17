"""The country interface: which countries a build covers, and how their shares merge.

Merging is where one country could silently overwrite another's place, so the tests pin
that a clash is an error, not a last-writer-wins.
"""

from __future__ import annotations

import pytest

from unigrids_pipeline import countries, reference_build
from unigrids_pipeline.countries import Contribution


def test_the_default_build_is_the_us_alone():
    assert countries.DEFAULT == ("us",)


def test_countries_are_parsed_in_order_without_repeats():
    assert countries.parse("us") == ("us",)
    assert countries.parse(" US, us ,") == ("us",)


@pytest.mark.parametrize("text", ["xx", "us,xx", "", " , "])
def test_an_unknown_or_missing_country_is_refused(text):
    with pytest.raises(ValueError):
        countries.parse(text)


def test_the_us_package_keeps_the_contract():
    us = countries.load("us")
    assert us.CODE == "us"
    assert us.NAME == "United States"
    assert callable(us.fetch) and callable(us.assemble) and callable(us.manifest_note)


def test_the_us_manifest_note_counts_its_own_places():
    us = countries.load("us")
    places = [{"kind": "nationalPark"}, {"kind": "nationalPark"}, {"kind": "statePark"}]
    assert us.manifest_note(places).startswith(
        "All 2 national parks with a full guide, and 1 more places on the map"
    )


def _share(prefix: str, **layers) -> Contribution:
    place_id = f"{prefix}-np-a"
    return Contribution(
        places=[{"id": place_id, "kind": "nationalPark"}],
        pois=[{"id": f"poi-{prefix}-a-sight"}],
        boundaries={place_id: {"bbox": [0, 0, 1, 1]}},
        guides={place_id: {"placeID": place_id}},
        expects_summary={place_id},
        **layers,
    )


def test_shares_merge_in_the_order_the_countries_were_named():
    first = _share("aa", transport={"motorways": [{"name": "1"}]}, trails=[{"id": "t1"}])
    second = _share("bb", transport={"motorways": [{"name": "2"}], "rail": []})
    merged = reference_build.merge([first, second])
    assert [place["id"] for place in merged.places] == ["aa-np-a", "bb-np-a"]
    assert list(merged.boundaries) == ["aa-np-a", "bb-np-a"]
    assert merged.transport == {"motorways": [{"name": "1"}, {"name": "2"}], "rail": []}
    assert merged.trails == [{"id": "t1"}]
    assert merged.expects_summary == {"aa-np-a", "bb-np-a"}


def test_a_layer_no_country_built_stays_unbuilt():
    merged = reference_build.merge([_share("aa"), _share("bb")])
    assert merged.transport is None
    assert merged.trails is None
    assert merged.documents is None
    assert merged.climate is None


def test_merging_does_not_change_a_share():
    first = _share("aa", transport={"motorways": [{"name": "1"}]})
    reference_build.merge([first, _share("bb", transport={"motorways": [{"name": "2"}]})])
    assert first.transport == {"motorways": [{"name": "1"}]}


def test_two_countries_cannot_build_one_place():
    with pytest.raises(ValueError, match="two countries"):
        reference_build.merge([_share("aa"), _share("aa")])


def test_two_countries_cannot_build_one_outline():
    first = _share("aa")
    second = _share("bb")
    second.boundaries["aa-np-a"] = {"bbox": [0, 0, 2, 2]}
    with pytest.raises(ValueError, match="boundaries"):
        reference_build.merge([first, second])
