"""How PAD-US's state park records become places."""

from __future__ import annotations

import json

import pytest

from unigrids_pipeline import ids, outline, state_parks


def _feature(
    name: str,
    state: str,
    acres: float = 10.0,
    access: str = "OA",
    *,
    west: float = -105.0,
    south: float = 39.0,
    size: float = 0.01,
    manager: str | None = None,
    held_by: str = "SPR",
) -> dict:
    east, north = west + size, south + size
    ring = [[west, south], [east, south], [east, north], [west, north], [west, south]]
    return {
        "type": "Feature",
        "properties": {
            "Unit_Nm": name, "State_Nm": state, "GIS_Acres": acres, "Pub_Access": access,
            "Loc_Mang": manager, "Mang_Name": held_by,
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


def test_local_land_padus_files_as_a_state_park_is_left_out():
    units = state_parks.merge([
        # Buffalo's traffic triangles and playgrounds, county, private and NGO parcels.
        _feature("4Th St", "NY", 0, manager="City of Buffalo", held_by="CITY"),
        _feature("Abbott & Potters Triangle", "NY", 0, manager="City of Buffalo",
                 held_by="CITY"),
        _feature("Baulder Street Playground", "NY", 2, held_by="CITY"),
        _feature("Decker", "NY", 30, held_by="CNTY"),
        _feature("Maddux Gift", "TN", 22, held_by="PVT"),
        _feature("South Waterfront Dog Park", "OR", 1, held_by="NGO"),
        _feature("LDC", "LA", 5, held_by="REG"),
        # A state body's record needs no designation in its name.
        _feature("Cheyenne Mountain", "CO", 2701, held_by="SPR"),
        _feature("Golden Gate Canyon", "CO", 12000, held_by="UNK"),
        # Run locally, but named as state park land.
        _feature("Scales Lake State Beach", "IN", 50, held_by="CNTY"),
        _feature("Veteran's Memorial State Park", "ID", 80, held_by="CITY"),
        _feature("Mendocino Woodlands State Park", "CA", 720, held_by="NGO"),
        _feature("Chehaw State Park", "GA", 800, held_by="JNT"),
        _feature("Big Ridge State Park", "TN", 40, held_by="TVA"),
    ])
    assert sorted(units) == [
        "padus-sp:CA:Mendocino Woodlands State Park",
        "padus-sp:CO:Cheyenne Mountain State Park",
        "padus-sp:CO:Golden Gate Canyon State Park",
        "padus-sp:GA:Chehaw State Park",
        "padus-sp:ID:Veteran's Memorial State Park",
        "padus-sp:IN:Scales Lake State Beach",
        "padus-sp:TN:Big Ridge State Park",
    ]


def test_a_parcel_named_for_a_park_joins_it_whoever_holds_it():
    units = state_parks.merge([
        _feature("Connecticut River Greenway State Park", "MA", 900,
                 manager="DCR Division of State Parks and Recreation", held_by="SDNR"),
        _feature("Connecticut River Greenway State Park", "MA", 12,
                 manager="New England Power Company", held_by="PVT"),
        # Not named for it, and not the state's: no part of the park.
        _feature("Connecticut River Greenway State Park/Durkee Lot", "MA", 3, held_by="PVT"),
        _feature("Durkee Lot", "MA", 3, held_by="PVT"),
    ])
    assert list(units) == ["padus-sp:MA:Connecticut River Greenway State Park"]
    park = units["padus-sp:MA:Connecticut River Greenway State Park"]
    assert park["acres"] == 900 + 12 + 3
    assert park["manager"] == "DCR Division of State Parks and Recreation"


@pytest.mark.parametrize("written", ["Unknown", "UNKNOWN", "Unk", "", "  ", None])
def test_an_unknown_manager_is_no_manager(written):
    units = state_parks.merge([_feature("Rock Island State Park", "WI", 900, manager=written)])
    unit = units["padus-sp:WI:Rock Island State Park"]
    assert unit["manager"] is None
    place, _ = state_parks._place(unit)
    assert "managedBy" not in place


def test_identifiers_carry_the_state_and_any_designation_but_state_park():
    assert state_parks.proposed_id("Cheyenne Mountain", "State Park", "CO") == (
        "sp-co-cheyenne-mountain"
    )
    assert state_parks.proposed_id("Refugio", "State Beach", "CA") == "sp-ca-refugio-state-beach"


# MARK: - Slivers across a state line
#
# Shapes after the real cases: Illinois Beach's acre in Wisconsin, Sterling Forest's six
# acres in New Jersey, High Point's empty record in New York beside the curated park.

_IL = "Illinois Department of Natural Resources"


def _build(tmp_path, features, places=None, boundaries=None, curated=None):
    (tmp_path / state_parks.FILE).write_text(
        json.dumps({"type": "FeatureCollection", "features": features})
    )
    places = places if places is not None else []
    boundaries = boundaries if boundaries is not None else {}
    registry = ids.Registry(tmp_path / "ids.json")
    state_parks.build(tmp_path, places, boundaries, registry, curated or [])
    return {place["id"]: place for place in places}, boundaries


def test_a_sliver_across_a_state_line_joins_the_park_beside_it(tmp_path):
    places, boundaries = _build(tmp_path, [
        _feature("Adeline Jay Geo-Karis Illinois Beach State Park", "IL", 3037,
                 west=-87.83, south=42.40, size=0.08, manager=_IL),
        _feature("Adeline Jay Geo-Karis Illinois Beach State Park", "WI", 1,
                 west=-87.81, south=42.48, size=0.002, manager=_IL),
    ])
    assert set(places) == {"sp-il-adeline-jay-geo-karis-illinois-beach"}
    park = places["sp-il-adeline-jay-geo-karis-illinois-beach"]
    assert park["states"] == ["IL"]
    assert park["facts"]["areaAcres"] == 3038
    assert set(boundaries) == {"sp-il-adeline-jay-geo-karis-illinois-beach"}


def test_a_sliver_managed_from_across_the_line_joins_its_park():
    units = state_parks.merge([
        _feature("Sterling Forest State Park", "NY", 18974,
                 west=-74.30, south=41.10, size=0.15, manager="New York State"),
        _feature("Sterling Forest State Park", "NJ", 6, west=-74.20, south=41.095, size=0.005,
                 manager="NY Office of Parks, Rec. and Historic Preservation"),
        _feature("Taconic State Park", "NY", 6737,
                 west=-73.55, south=42.00, size=0.10, manager="New York State"),
        _feature("Taconic State Park", "MA", 11, west=-73.45, south=42.05, size=0.004,
                 manager="NY Office of Parks, Rec. and Historic Preservation"),
    ])
    joined = state_parks.fold_slivers(units)
    assert joined == {
        "padus-sp:NJ:Sterling Forest State Park": "padus-sp:NY:Sterling Forest State Park",
        "padus-sp:MA:Taconic State Park": "padus-sp:NY:Taconic State Park",
    }
    assert set(units) == {
        "padus-sp:NY:Sterling Forest State Park", "padus-sp:NY:Taconic State Park",
    }
    assert units["padus-sp:NY:Taconic State Park"]["acres"] == 6748
    assert len(units["padus-sp:NY:Taconic State Park"]["polygons"]) == 2


def test_twin_parks_across_a_line_both_stay():
    units = state_parks.merge([
        # Each run by its own state.
        _feature("Bear Lake State Park", "ID", 969, west=-111.39, south=42.00, size=0.12,
                 manager="Idaho Parks and Recreation"),
        _feature("Bear Lake State Park", "UT", 570, west=-111.40, south=41.84, size=0.16,
                 manager="Utah State Department of State Parks"),
        _feature("Pymatuning State Park", "PA", 20335, west=-80.50, south=41.50, size=0.2,
                 manager="PA Bureau of State Parks"),
        _feature("Pymatuning State Park", "OH", 4891, west=-80.53, south=41.55, size=0.03,
                 manager="Ohio Department of Natural Resources"),
        _feature("White Clay Creek State Park", "DE", 3520, west=-75.75, south=39.70,
                 size=0.05, manager="State of Delaware"),
        _feature("White Clay Creek State Park", "PA", 2131, west=-75.80, south=39.72,
                 size=0.05, manager="PA Bureau of State Parks"),
        # Small beside its twin, but Virginia's own.
        _feature("Mayo River State Park", "NC", 1850, west=-80.02, south=36.39, size=0.15,
                 manager="NC DENR, Division of Parks and Recreation"),
        _feature("Mayo River State Park", "VA", 56, west=-79.99, south=36.542, size=0.003,
                 manager="VA Dept of Conservation and Recreation"),
    ])
    assert state_parks.fold_slivers(units) == {}
    assert len(units) == 8


def test_a_same_named_park_far_away_is_not_a_sliver():
    units = state_parks.merge([
        _feature("Lincoln State Park", "IN", 1746, west=-86.99, south=38.10, size=0.05,
                 manager="Indiana DNR, State Parks and Reservoirs Division"),
        _feature("Lincoln State Park", "NY", 0, west=-78.87, south=42.90, size=0.001,
                 manager="City of Buffalo"),
    ])
    assert state_parks.fold_slivers(units) == {}
    assert len(units) == 2


def test_a_sliver_beside_a_curated_park_is_left_out(tmp_path):
    ring = [(-74.80, 41.20), (-74.55, 41.20), (-74.55, 41.35), (-74.80, 41.35)]
    curated_place = {
        "id": "sp-high-point", "name": "High Point", "designation": "State Park",
        "kind": "statePark", "states": ["NJ"], "facts": {"areaAcres": 14982},
    }
    boundaries = {"sp-high-point": {"bbox": [41.20, -74.80, 41.35, -74.55],
                                    "polygons": [[outline.encode(ring)]]}}
    curated = [{"id": "sp-high-point", "name": "High Point", "designation": "State Park",
                "kind": "statePark", "states": ["NJ"], "padus": ["High Point State Park"]}]
    places, boundaries = _build(
        tmp_path,
        [_feature("High Point State Park", "NY", 0, west=-74.6748, south=41.3478, size=0.0004,
                  manager="NJ Department of Environmental Protection")],
        places=[curated_place], boundaries=boundaries, curated=curated,
    )
    assert set(places) == {"sp-high-point"}
    assert set(boundaries) == {"sp-high-point"}
