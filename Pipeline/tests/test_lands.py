"""The rules ``lands_build`` applies to the federal sources' names and lines."""

from __future__ import annotations

from unigrids_pipeline import lands_build


def test_title_case_handles_initials_small_words_and_mc() -> None:
    assert lands_build.title_case("J. N. DING DARLING") == "J. N. Ding Darling"
    assert lands_build.title_case("BOSQUE DEL APACHE") == "Bosque del Apache"
    assert lands_build.title_case("MCKAY CREEK") == "McKay Creek"
    assert lands_build.title_case("D'ARBONNE") == "D'Arbonne"
    assert lands_build.title_case("LAKE OF THE WOODS") == "Lake of the Woods"
    assert lands_build.title_case("SAN BERNARDINO-SAN ANDRES") == "San Bernardino-San Andres"


def test_refuge_names_split_off_their_designation() -> None:
    assert lands_build._refuge_name("CHINCOTEAGUE NATIONAL WILDLIFE REFUGE") == (
        "Chincoteague",
        "National Wildlife Refuge",
    )
    assert lands_build._refuge_name("WICHITA MOUNTAINS WILDLIFE REFUGE") == (
        "Wichita Mountains",
        "Wildlife Refuge",
    )
    assert lands_build._refuge_name("NATIONAL ELK REFUGE") == ("National Elk", "Refuge")
    assert lands_build._refuge_name("SILVIO O. CONTE NATIONAL FISH AND WILDLIFE REFUGE") == (
        "Silvio O. Conte",
        "National Fish and Wildlife Refuge",
    )
    assert lands_build._refuge_name("JOHN HEINZ NATIONAL WILDLIFE REFUGE AT TINICUM") == (
        "John Heinz at Tinicum",
        "National Wildlife Refuge",
    )
    assert lands_build._refuge_name(
        "JULIA BUTLER HANSEN REFUGE FOR THE COLUMBIAN WHITE TAIL DEER"
    ) == ("Julia Butler Hansen", "Refuge for the Columbian White Tail Deer")
    assert lands_build._refuge_name("ST. MARKS NATIONAL WILDLIFE REFUGE") == (
        "St. Marks",
        "National Wildlife Refuge",
    )


def test_blm_names_read_the_designation_from_the_name_then_the_code() -> None:
    assert lands_build._blm_name(
        {"NCA_NAME": "King Range National Conservation Area", "NLCS_ID": "x"}
    ) == ("King Range", "National Conservation Area")
    assert lands_build._blm_name(
        {"NCA_NAME": "Sloan Canyon", "sma_code": "BLM_NCA", "NLCS_ID": "x"}
    ) == ("Sloan Canyon", "National Conservation Area")
    assert lands_build._blm_name({"NCA_NAME": "Somewhere", "NLCS_ID": "x"}) == (
        "Somewhere",
        lands_build.BLM_FALLBACK_DESIGNATION,
    )
    # An override wins over a code that says otherwise.
    assert lands_build._blm_name(
        {"NCA_NAME": "Red Cliffs", "sma_code": "BLM_NM", "NLCS_ID": "NLCS000855"}
    ) == ("Red Cliffs", "National Conservation Area")


def test_chain_joins_pieces_that_meet_and_keeps_real_gaps() -> None:
    a = [(0.0, 0.0), (1.0, 0.0)]
    b = [(2.0, 0.0), (1.0, 0.0)]  # reversed, meets a's end
    c = [(2.0, 0.0), (3.0, 0.0)]
    far = [(10.0, 0.0), (11.0, 0.0)]
    paths = lands_build._chain([a, c, far, b])
    lengths = sorted(len(path) for path in paths)
    assert lengths == [2, 4]
    joined = max(paths, key=len)
    assert {joined[0], joined[-1]} == {(0.0, 0.0), (3.0, 0.0)}


def test_antimeridian_keeps_the_larger_side() -> None:
    west = [[(-170.0, 52.0), (-169.0, 52.0), (-169.0, 53.0), (-170.0, 53.0)]]
    east = [[(173.0, 52.5), (173.1, 52.5), (173.1, 52.6)]]
    kept = lands_build._one_side_of_the_antimeridian([west, east])
    assert kept == [west]


def test_water_routes_are_not_hiking_trails() -> None:
    from unigrids_pipeline import trail_catalogue

    assert trail_catalogue._is_water_route("Non-Motorized Watercraft")
    assert trail_catalogue._is_water_route("Motorized Watercraft")
    assert not trail_catalogue._is_water_route("Hiker/Pedestrian, Non-Motorized Watercraft")
    assert not trail_catalogue._is_water_route("Hike")


def test_small_words_a_source_capitalised_are_lowered() -> None:
    assert lands_build.lower_small_words("Statue Of Liberty") == "Statue of Liberty"
    assert lands_build.lower_small_words("War In The Pacific") == "War in the Pacific"
    assert (
        lands_build.lower_small_words("Arlington House, The Robert E. Lee Memorial")
        == "Arlington House, The Robert E. Lee Memorial"
    )
    assert lands_build.lower_small_words("James A Garfield") == "James A Garfield"
    assert lands_build.lower_small_words("The Narrows") == "The Narrows"
