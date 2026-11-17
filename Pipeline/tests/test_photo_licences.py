"""Every photograph carries its licence, and is public domain only when the licence says so.

The app shows a public-domain photograph with a bare credit and anything else with its
licence (``GuideImage.creditLine``), so a wrong ``isPublicDomain`` drops a licence the
photographer is owed.
"""

from __future__ import annotations

import pytest

from unigrids_pipeline import reference_content
from unigrids_pipeline.countries import common


@pytest.mark.parametrize(
    "licence", ["Public domain", "Public Domain", "PD", "PD-US", "CC0", "CC0 1.0"]
)
def test_public_domain_licences(licence):
    assert reference_content.is_public_domain_licence(licence)
    assert reference_content.is_reusable_licence(licence)


@pytest.mark.parametrize("licence", ["CC BY 4.0", "CC BY-SA 3.0", "PDL 1.0"])
def test_licences_that_ask_for_credit_are_reusable_but_not_public_domain(licence):
    assert not reference_content.is_public_domain_licence(licence)
    assert reference_content.is_reusable_licence(licence)


@pytest.mark.parametrize("licence", [None, "", "All rights reserved", "Copyrighted free use"])
def test_other_licences_are_not_reused(licence):
    assert not reference_content.is_public_domain_licence(licence)
    assert not reference_content.is_reusable_licence(licence)


def test_nps_photographs_are_chosen_with_their_licence():
    images = [{"url": "a", "credit": "NPS/Jacob W. Frank", "title": "Arch"}]
    (chosen,) = reference_content.choose_photos(images)
    assert chosen["licence"] == reference_content.NPS_PHOTO_LICENCE
    assert "licence" not in images[0]


def test_a_public_domain_photograph_carries_a_bare_credit():
    image = {"url": "a", "credit": "NPS / Jane Doe", "licence": "Public domain"}
    assert common.guide_image(image) == {
        "credit": "NPS / Jane Doe", "isPublicDomain": True, "url": "a"
    }


@pytest.mark.parametrize("licence", ["CC BY-SA 4.0", "PDL 1.0"])
def test_a_licensed_photograph_is_not_marked_public_domain(licence):
    image = {"url": "a", "credit": "Jane Doe", "licence": licence, "title": "Peak"}
    entry = common.guide_image(image, asset_name="np-x-a.jpg")
    assert entry["isPublicDomain"] is False
    assert entry["licence"] == licence
    assert entry["assetName"] == "np-x-a.jpg" and "url" not in entry


@pytest.mark.parametrize(
    "image",
    [
        {"url": "a", "credit": "NPS"},
        {"url": "a", "credit": "Jane Doe", "licence": "All rights reserved"},
        {"url": "a", "licence": "Public domain"},
        {"url": "a", "credit": " ", "licence": "Public domain"},
    ],
)
def test_a_photograph_without_credit_or_reusable_licence_fails_the_build(image):
    with pytest.raises(common.UnlicensedPhotographError):
        common.guide_image(image)


def test_a_pdl_photograph_on_commons_is_not_public_domain():
    image = common.wikimedia_image({
        "thumbURL": "https://upload.wikimedia.org/x.jpg",
        "licence": "PDL 1.0",
        "artist": "Ministry of the Environment",
        "descriptionURL": "https://commons.wikimedia.org/wiki/File:X.jpg",
    })
    assert image is not None
    assert image["isPublicDomain"] is False
    assert image["licence"] == "PDL 1.0"


def test_every_curated_hero_states_its_licence():
    """A hero chosen by hand bypasses the NPS photo policy, so its licence is written
    down beside it rather than assumed."""
    for path in reference_content.guide_paths():
        override = (reference_content.guide(path.stem) or {}).get("heroOverride")
        if override:
            assert reference_content.is_reusable_licence(override.get("licence")), path.name


def test_a_commons_photograph_on_the_us_path_names_the_author_commons_assumed():
    image = common.wikimedia_image({
        "thumbURL": "https://upload.wikimedia.org/x.jpg",
        "licence": "CC BY 2.5",
        "artist": "No machine-readable author provided. Miskatonic assumed (based on "
                  "copyright claims).",
        "credit": "No machine-readable source provided. Own work assumed (based on "
                  "copyright claims).",
        "descriptionURL": "https://commons.wikimedia.org/wiki/File:X.jpg",
    })
    assert image is not None
    assert image["credit"] == "Miskatonic, via Wikimedia Commons"


def test_a_commons_photograph_with_no_author_is_credited_to_commons():
    record = {
        "thumbURL": "https://upload.wikimedia.org/x.jpg",
        "licence": "CC BY-SA 3.0",
        "artist": None,
        "credit": "",
        "descriptionURL": "https://commons.wikimedia.org/wiki/File:X.jpg",
    }
    assert common.wikimedia_image(record)["credit"] == "Wikimedia Commons"
    assert common.wikimedia_image({**record, "uploader": "Snowgoose"})["credit"] == (
        "Snowgoose, via Wikimedia Commons"
    )
