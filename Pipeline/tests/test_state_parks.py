"""How PAD-US's state park records become places."""

from __future__ import annotations

from unigrids_pipeline import state_parks


def _feature(name: str, state: str, acres: float = 10.0, access: str = "OA") -> dict:
    ring = [[-105.0, 39.0], [-104.99, 39.0], [-104.99, 39.01], [-105.0, 39.01], [-105.0, 39.0]]
    return {
        "type": "Feature",
        "properties": {
            "Unit_Nm": name, "State_Nm": state, "GIS_Acres": acres, "Pub_Access": access,
        },
        "geometry": {"type": "Polygon", "coordinates": [ring]},
    }


def test_names_split_off_their_designation():
    assert state_parks.clean_name("Cheyenne Mountain State Park") == (
        "Cheyenne Mountain", "State Park",
    )
    assert state_parks.clean_name("Refugio State Beach") == ("Refugio", "State Beach")
    assert state_parks.clean_name("Jerome State Historic Park") == ("Jerome", "State Historic Park")
    assert state_parks.clean_name("Cheyenne Mountain") == ("Cheyenne Mountain", "State Park")
    assert state_parks.clean_name("BIG SPRING STATE PARK") == ("Big Spring", "State Park")


def test_a_compound_record_keeps_the_part_that_is_the_park():
    assert state_parks.clean_name(
        "Bonny Lake State Park/South Republican State Wildlife Area"
    ) == ("Bonny Lake", "State Park")


def test_records_merge_by_name_within_a_state_and_not_across():
    units = state_parks.merge([
        _feature("Bonny Lake State Park", "CO", 1445),
        _feature("Bonny Lake State Park/South Republican State Wildlife Area", "CO", 1853),
        _feature("Lake State Park", "NY"),
        _feature("Lake State Park", "OH"),
    ])
    assert set(units) == {
        "padus-sp:CO:Bonny Lake State Park",
        "padus-sp:NY:Lake State Park",
        "padus-sp:OH:Lake State Park",
    }
    bonny = units["padus-sp:CO:Bonny Lake State Park"]
    assert bonny["acres"] == 1445 + 1853
    assert len(bonny["polygons"]) == 2


def test_closed_units_and_curated_parks_are_left_out():
    curated = [{"kind": "statePark", "states": ["CO"], "padus": ["Roxborough%"]}]
    units = state_parks.merge(
        [
            _feature("Roxborough State Park", "CO"),
            _feature("Secret State Park", "CO", access="XA"),
            _feature("Golden Gate Canyon State Park", "CO"),
        ],
        state_parks._curated_patterns(curated),
    )
    assert list(units) == ["padus-sp:CO:Golden Gate Canyon State Park"]


def test_identifiers_carry_the_state_and_any_designation_but_state_park():
    assert state_parks.proposed_id("Cheyenne Mountain", "State Park", "CO") == (
        "sp-co-cheyenne-mountain"
    )
    assert state_parks.proposed_id("Refugio", "State Beach", "CA") == "sp-ca-refugio-state-beach"
