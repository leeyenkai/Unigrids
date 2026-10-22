"""The rules that decide whether a Wikipedia lead may describe a place."""

from __future__ import annotations

from unigrids_pipeline import outline, wikipedia_match


def _square(lon: float, lat: float, half: float = 0.05) -> dict:
    ring = [
        (lon - half, lat - half), (lon + half, lat - half), (lon + half, lat + half),
        (lon - half, lat + half), (lon - half, lat - half),
    ]
    return {"bbox": [lat - half, lon - half, lat + half, lon + half],
            "polygons": [[outline.encode(ring)]]}


PLACE = {
    "id": "sp-co-cheyenne-mountain", "name": "Cheyenne Mountain", "designation": "State Park",
    "kind": "statePark", "states": ["CO"], "centre": {"latitude": 38.73, "longitude": -104.82},
}


def _page(title: str, lat: float, lon: float, **extra) -> dict:
    return {"title": title, "extract": "Cheyenne Mountain State Park is a park. It is nice.",
            "url": f"https://en.wikipedia.org/wiki/{title}", "disambiguation": False,
            "latitude": lat, "longitude": lon, "image": None, **extra}


def test_candidate_titles_try_the_full_name_then_the_state():
    assert wikipedia_match.candidate_titles(PLACE) == [
        "Cheyenne Mountain State Park", "Cheyenne Mountain State Park (Colorado)",
    ]
    byway = {"name": "Beartooth Highway", "designation": "All-American Road",
             "kind": "scenicByway", "states": ["MT"]}
    assert wikipedia_match.candidate_titles(byway)[0] == "Beartooth Highway"


def test_an_article_inside_the_outline_matches():
    pages = {"Cheyenne Mountain State Park": _page("Cheyenne Mountain State Park", 38.73, -104.82)}
    match = wikipedia_match._match(PLACE, pages, _square(-104.82, 38.73), None)
    assert isinstance(match, dict)


def test_an_article_far_from_the_place_is_rejected():
    pages = {"Cheyenne Mountain State Park": _page("Cheyenne Mountain State Park", 40.0, -105.5)}
    decision = wikipedia_match._match(PLACE, pages, _square(-104.82, 38.73), None)
    assert isinstance(decision, str) and "km away" in decision


def test_disambiguation_and_unplaced_articles_are_rejected():
    pages = {
        "Cheyenne Mountain State Park": _page(
            "Cheyenne Mountain State Park", 38.73, -104.82, disambiguation=True
        ),
        "Cheyenne Mountain State Park (Colorado)": _page(
            "Cheyenne Mountain State Park (Colorado)", None, None
        ),
    }
    decision = wikipedia_match._match(PLACE, pages, _square(-104.82, 38.73), None)
    assert "disambiguation" in decision and "no coordinates" in decision


def test_a_redirect_to_another_subject_is_rejected():
    pages = {"Cheyenne Mountain State Park": _page("Colorado Springs", 38.73, -104.82)}
    decision = wikipedia_match._match(PLACE, pages, _square(-104.82, 38.73), None)
    assert isinstance(decision, str) and "resolved to" in decision


def test_the_lead_is_cut_to_three_sentences_and_loses_pronunciations():
    extract = (
        "Big Bend (/bɪɡ bɛnd/) is a place. Second sentence here. Third one too. "
        "Fourth is dropped."
    )
    assert wikipedia_match.lead(extract) == (
        "Big Bend is a place. Second sentence here. Third one too."
    )
