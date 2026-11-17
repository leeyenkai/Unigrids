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
    city = _page("Colorado Springs", 38.73, -104.82,
                 extract="Colorado Springs is a city. Cheyenne Mountain State Park lies south.")
    pages = {"Cheyenne Mountain State Park": city}
    decision = wikipedia_match._match(PLACE, pages, _square(-104.82, 38.73), None)
    assert isinstance(decision, str) and "resolved to" in decision


def test_a_title_names_the_place_in_whole_words():
    assert wikipedia_match._title_names_place(
        "Lamar Alexander Rocky Fork State Park", "Rocky Fork"
    )
    assert wikipedia_match._title_names_place("Coconino National Forest (Arizona)", "Coconino")
    assert not wikipedia_match._title_names_place("Hartwell Lakeside Park", "Hart")


def test_a_title_may_name_the_place_in_the_plural_or_the_singular():
    names = wikipedia_match._title_names_place
    assert names("Wyandotte Caves", "Wyandotte Cave")
    assert names("Wyandotte Cave", "Wyandotte Caves")
    assert names("Hell Canyon Passes (Idaho)", "Hell Canyon Pass")
    assert names("Battle Prairies Natural Area", "Battle Prairie")
    assert names("Harbor Batteries", "Harbor Battery")
    # Only in number, and only the last word: other endings and other words stay distinct.
    assert not names("Wyandotte Cavern", "Wyandotte Cave")
    assert not names("Wyandottes Cave", "Wyandotte Cave")
    assert not names("Hartwell Lakeside Park", "Hart")
    assert not names("Harts Lakeside Park", "Hart Lake")


HART = {
    "id": "sp-ga-hart", "name": "Hart", "designation": "State Park", "kind": "statePark",
    "states": ["GA"], "centre": {"latitude": 34.37, "longitude": -82.91},
}


def _hart_match(extract: str) -> dict | str:
    pages = {"Hart State Park": _page("Hartwell Lakeside Park", 34.376, -82.911, extract=extract)}
    return wikipedia_match._match(HART, pages, _square(-82.91, 34.37), None)


def test_a_renamed_park_matches_when_its_article_says_so():
    renamed = _hart_match(
        "Hartwell Lakeside Park, formerly known as Hart State Park, is a 147 acres (59 ha) "
        "park in Hartwell, in northeast Georgia."
    )
    assert isinstance(renamed, dict) and renamed["title"] == "Hartwell Lakeside Park"


def test_hart_is_not_found_in_hartwell_without_the_article_saying_so():
    for extract in (
        # No word of Hart State Park at all.
        "Hartwell Lakeside Park is a park in Hartwell, in northeast Georgia.",
        # Named, but as a neighbour, not as what the subject used to be.
        "Hartwell Lakeside Park is a city park beside Hart State Park.",
        # The former name belongs to something after the subject's verb.
        "Hartwell Lakeside Park is a city park. Its neighbour, formerly known as Hart State "
        "Park, closed.",
        # Formerly something else.
        "Hartwell Lakeside Park, formerly known as Hartwell State Park, is a park.",
    ):
        decision = _hart_match(extract)
        assert isinstance(decision, str) and "resolved to" in decision, extract


def test_the_ways_an_article_says_what_it_was_called():
    renamed = wikipedia_match._subject_names_place
    park = {"name": "Old Davidsonville", "designation": "State Park", "kind": "statePark"}
    assert renamed("Davidsonville Historic State Park (formerly Old Davidsonville State Park) "
                   "is a 163-acre Arkansas state park.", park)
    assert renamed("Davidsonville Park, previously known as Old Davidsonville State Park, "
                   "is a park.", park)
    assert renamed("Davidsonville Park, formerly named Old Davidsonville State Park, is a park.",
                   park)
    assert renamed("Davidsonville Park, renamed from Old Davidsonville State Park in 2001, is "
                   "a park.", park)
    toltec = {"name": "Toltec Mounds Archeological", "designation": "State Park",
              "kind": "statePark"}
    assert renamed('Plum Bayou Mounds Archeological State Park (3 LN 42), formerly known as '
                   '"Toltec Mounds Archeological State Park", also known as Knapp Mounds, is '
                   'an archaeological site.', toltec)


def test_a_park_merged_under_a_new_title_matches():
    renamed = wikipedia_match._subject_names_place
    lead = (
        "Colorado River State Historic Park, formerly Yuma Crossing State Historic Park and "
        "Yuma Quartermaster Depot State Historic Park, and now one of the Yuma Crossing and "
        "Associated Sites. It is an Arizona state park in the city of Yuma."
    )
    for name in ("Yuma Crossing", "Yuma Quartermaster Depot"):
        place = {"name": name, "designation": "State Historic Park", "kind": "statePark"}
        assert renamed(lead, place), name
    other = {"name": "Yuma Territorial Prison", "designation": "State Historic Park",
             "kind": "statePark"}
    assert not renamed(lead, other)


def test_an_article_that_also_goes_by_the_full_name_matches():
    named = wikipedia_match._subject_names_place

    def park(name: str, designation: str = "State Park") -> dict:
        return {"name": name, "designation": designation, "kind": "statePark"}

    assert named("McCroskey State Park\u2014officially Mary Minerva McCroskey State Park\u2014is "
                 "a public recreation area.", park("Mary Minerva McCroskey"))
    assert named("The Illinois Beach State Park (officially the Adeline Jay Geo-Karis Illinois "
                 "Beach State Park) is a state park of Illinois.",
                 park("Adeline Jay Geo-Karis Illinois Beach"))
    assert named("R. B. Winter State Park (also known as Raymond B. Winter State Park) is a "
                 "Pennsylvania state park.", park("Raymond B. Winter"))
    assert named("Clarence Fahnestock Memorial State Park, also known as Fahnestock State "
                 "Park, is a state park.", park("Clarence Fahnestock Memorial"))
    refuge = {"name": "Arthur R. Marshall Loxahatchee",
              "designation": "National Wildlife Refuge", "kind": "wildlifeRefuge"}
    assert named("The Arthur R. Marshall Loxahatchee National Wildlife Refuge is a "
                 "wildlife sanctuary.", refuge)


def test_a_name_inside_a_longer_one_or_a_neighbours_does_not_match():
    named = wikipedia_match._subject_names_place
    glen_elder = {"name": "Glen Elder", "designation": "State Park", "kind": "statePark"}
    for extract in (
        # Another thing's alias.
        "Waconda Lake, also known as Glen Elder Reservoir, is a reservoir.",
        # The park named only after the verb.
        "Waconda Lake is a reservoir. Glen Elder State Park is located on its north shore.",
        # The name as the start of a longer one.
        "Glen Elder State Park Marina, also known as the marina, is a marina.",
        "The lake, also known as Glen Elder State Park Lake, is a lake.",
    ):
        assert not named(extract, glen_elder), extract
    # One of two parks under one title, named after the verb, is not the subject.
    andrae = {"name": "Terry Andrae", "designation": "State Park", "kind": "statePark"}
    assert not named("Kohler-Andrae State Park comprises two adjacent Wisconsin state parks. "
                     "They are managed as one unit. Terry Andrae State Park, established in "
                     "1927, and John Michael Kohler State Park.", andrae)


def test_a_state_park_its_article_says_the_state_gave_up_is_left_out():
    left = wikipedia_match.left_state_system
    hart = {"name": "Hart", "designation": "State Park", "kind": "statePark"}
    assert left("Hartwell Lakeside Park, formerly known as Hart State Park, is a 147 acres "
                "(59 ha) park in Hartwell, in northeast Georgia. The park is named after "
                "Nancy Hart.", hart)
    # Renamed, still a state park: by its new name or by what its first sentence says.
    patricks = {"name": "Patrick's Point", "designation": "State Park", "kind": "statePark"}
    assert not left("Sue-meg State Park (formerly Patrick's Point State Park) is a 640-acre "
                    "California State Park.", patricks)
    jamesport = {"name": "Jamesport", "designation": "State Park", "kind": "statePark"}
    assert not left("Hallock Preserve (formerly Jamesport State Park) is a 225-acre state park "
                    "and nature preserve.", jamesport)
    # Also known as, not formerly: the same park under two names.
    florewood = {"name": "Florewood River Plantation", "designation": "State Park",
                 "kind": "statePark"}
    assert not left("Florewood Park, also known as Florewood River Plantation State Park, is "
                    "a public recreation area.", florewood)
    # Only state parks: a refuge renamed is still a refuge.
    refuge = {"name": "Old", "designation": "National Wildlife Refuge",
              "kind": "wildlifeRefuge"}
    assert not left("New Refuge, formerly Old National Wildlife Refuge, is a refuge.", refuge)


def test_a_landmark_is_not_matched_by_a_former_name():
    # A bare name is often an organisation's or a village's too.
    landmark = {"name": "Audubon Canyon Ranch", "designation": "National Natural Landmark",
                "kind": "naturalLandmark"}
    assert not wikipedia_match._subject_names_place(
        "All Hands Ecology (formerly Audubon Canyon Ranch) is a 501(c)(3) not-for-profit "
        "environmental conservation and education organization.", landmark
    )


def test_the_lead_is_cut_to_three_sentences_and_loses_pronunciations():
    extract = (
        "Big Bend (/bɪɡ bɛnd/) is a place. Second sentence here. Third one too. "
        "Fourth is dropped."
    )
    assert wikipedia_match.lead(extract) == (
        "Big Bend is a place. Second sentence here. Third one too."
    )


def test_a_park_its_article_calls_closed_is_recognised():
    closed = [
        "Bonny Lake State Park is a former state park located in Yuma County, Colorado.",
        "Walnut Creek State Park was a former Oklahoma State Park on the north shore.",
        "The former Arrowhead State Park, now known as the Arrowhead Area at Lake Eufaula.",
        "Fairfield Lake State Park was a state park located in Freestone County, Texas.",
    ]
    open_ = [
        "Crowley's Ridge State Park is a park located on the former homesite of Benjamin "
        "Crowley.",
        "Gathland State Park occupies the former estate of George Alfred Townsend.",
        "Fort Ebey State Park is a public recreation area. It was a former army fort.",
    ]
    assert all(wikipedia_match.says_closed(text) for text in closed)
    assert not any(wikipedia_match.says_closed(text) for text in open_)


def test_an_article_about_the_town_a_park_is_named_for_is_rejected():
    towns = [
        "Boswell is a town in Choctaw County, Oklahoma, United States.",
        "Jackson Lake is an unincorporated community and a census-designated place (CDP) "
        "located in and governed by Morgan County, Colorado.",
        "Elkhorn is a census-designated place (CDP) in Jefferson County, Montana.",
    ]
    parks = [
        "Bannack is a ghost town in Beaverhead County, Montana.",
        "Mount Diablo is a mountain of the Diablo Range, in Contra Costa County.",
        "Boswell State Park is a park in the town of Boswell.",
        "Fort Mott was part of the Harbor Defenses of the Delaware. The city lies north.",
    ]
    assert all(wikipedia_match.describes_settlement(text) for text in towns)
    assert not any(wikipedia_match.describes_settlement(text) for text in parks)
    boswell = {**PLACE, "name": "Boswell", "states": ["OK"]}
    pages = {"Boswell State Park": _page("Boswell, Oklahoma", 38.73, -104.82,
                                         extract=towns[0])}
    decision = wikipedia_match._match(boswell, pages, _square(-104.82, 38.73), None)
    assert isinstance(decision, str) and "settlement" in decision
