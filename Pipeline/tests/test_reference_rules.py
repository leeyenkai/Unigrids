"""Small rules the reference build applies to NPS text and figures."""

from __future__ import annotations

import json
from datetime import date, timedelta

import pytest

from unigrids_pipeline import (
    climate,
    park_elevation,
    reference_build,
    reference_content,
    visitation,
)
from unigrids_pipeline.countries import Contribution, common
from unigrids_pipeline.countries.us import assembly


def test_dated_notices_are_dropped_and_the_rest_kept():
    text = (
        "***CLOSED as of August 31, 2026*** The centre has exhibits and a film. "
        "Scheduled to open late October 2026. Built in 1936 by the CCC."
    )
    assert assembly._without_notices(text) == (
        "The centre has exhibits and a film. Built in 1936 by the CCC."
    )
    assert assembly._without_notices("Closed for 2026.") is None
    assert assembly._without_notices("Open May 9–October 31, 2025.") is None
    assert assembly._without_notices("Open daily, 9 to 5.") == "Open daily, 9 to 5."


def test_stamp_labels_lose_stale_status():
    assert assembly._stamp_label("A.G. Gaston Motel (Temporarily Closed)") == (
        "A.G. Gaston Motel"
    )
    assert assembly._stamp_label("Fort Museum - Closed for Renovation") == "Fort Museum"
    assert assembly._stamp_label("Kolb Studio") == "Kolb Studio"


def test_known_source_damage_is_repaired():
    assert common.clean("Pools of ?Ohe?o") == "Pools of ʻOheʻo"


def test_visitation_averages_full_years_and_totals_the_latest():
    by_month = {
        (year, month): 1000 * month + year - 2022
        for year in visitation.YEARS
        for month in range(1, 13)
    }
    entry = visitation.reduce(by_month)
    assert entry is not None
    assert entry["years"] == [2022, 2025]
    assert entry["monthly"][0] == round((1000 + 1000 + 1 + 1000 + 2 + 1000 + 3) / 4)
    assert entry["annual"] == sum(1000 * month + 3 for month in range(1, 13))


def test_visitation_with_a_missing_month_has_no_monthly_figures():
    by_month = {(year, month): 10 for year in visitation.YEARS for month in range(1, 13)}
    del by_month[(2023, 7)]
    entry = visitation.reduce(by_month)
    assert entry is not None and "monthly" not in entry and entry["annual"] == 120


# MARK: - National parks from the NPS API


class _API:
    """The slice of ``assembly._NPSData`` a national park reads, from rows given here."""

    def __init__(self, places=(), centres=(), camps=()):
        self.fees_passes: dict = {}
        self._places, self._centres, self._camps = list(places), list(centres), list(camps)

    def places_for(self, code):
        return self._places

    def visitor_centres_for(self, code):
        return self._centres

    def campgrounds_for(self, code):
        return self._camps

    def stamp_labels_for(self, code):
        return []


def _row(place_id: str) -> dict:
    return next(row for _, row in reference_content.national_park_rows() if row["id"] == place_id)


def _park(tmp_path, row, park, api, guide=None, monkeypatch=None):
    if monkeypatch is not None:
        monkeypatch.setattr(assembly.reference_content, "guide", lambda place_id: guide)
    return assembly._national_park(row, park, {}, api, None, tmp_path, None)


def test_parks_sharing_an_api_record_keep_their_own_centres(tmp_path):
    # SEKI's one coordinate lies in Kings Canyon; Sequoia must not be pinned there.
    seki = {"parkCode": "seki", "latitude": "36.71277", "longitude": "-118.58743"}
    for place_id in ("np-sequoia", "np-kings-canyon"):
        row = _row(place_id)
        assert row["npsApiCode"] == "SEKI"
        place, _, _ = _park(tmp_path, row, seki, _API())
        assert place["centre"] == {"latitude": row["centre"][0], "longitude": row["centre"][1]}


def test_a_park_with_its_own_api_record_takes_the_api_centre(tmp_path):
    row = _row("np-zion")
    place, _, _ = _park(tmp_path, row, {"latitude": "37.29839", "longitude": "-113.0263"}, _API())
    assert place["centre"] == {"latitude": 37.29839, "longitude": -113.0263}


def test_a_sight_and_a_facility_of_one_name_get_different_identifiers(tmp_path, monkeypatch):
    row = {**_row("np-denali"), "npsApiCode": None}
    here = {"latitude": "63.45", "longitude": "-150.86"}
    guide = {"sights": [{"name": "Wonder Lake", "location": [63.465, -150.84]},
                        {"name": "Old Courthouse", "location": [63.46, -150.8]}]}
    api = _API(
        centres=[{"name": "Old Courthouse", **here}, {"name": "Old Courthouse", **here},
                 {"name": "Eielson", **here}],
        camps=[{"name": "Wonder Lake", **here}, {"name": "Eielson", **here}],
    )
    _, _, pois = _park(tmp_path, row, {}, api, guide, monkeypatch)
    by_id = {poi["id"]: poi["kind"] for poi in pois}
    assert len(by_id) == len(pois)
    assert by_id == {
        "poi-denali-wonder-lake": "sight",
        "poi-denali-old-courthouse": "sight",
        "poi-denali-old-courthouse-visitor-centre": "visitorCentre",
        "poi-denali-eielson": "visitorCentre",
        "poi-denali-wonder-lake-campground": "campground",
        "poi-denali-eielson-campground": "campground",
    }


def test_no_two_points_of_interest_in_a_build_share_an_identifier():
    share = Contribution(pois=[
        {"id": "poi-denali-wonder-lake", "kind": "sight"},
        {"id": "poi-denali-wonder-lake", "kind": "campground"},
    ])
    with pytest.raises(ValueError, match="poi-denali-wonder-lake"):
        reference_build.merge([share])


# MARK: - Elevation


def _measured(tmp_path, facts: dict) -> dict:
    (tmp_path / park_elevation.FILE).write_text(
        json.dumps({"DENA": {"min": 70.4, "max": 6178.2, "pixelSize": 60}})
    )
    place = {"id": "np-denali", "kind": "nationalPark", "npsParkCode": "DENA", "facts": facts}
    park_elevation.attach([place], tmp_path)
    return place["facts"]


def test_a_published_summit_is_not_labelled_as_measured(tmp_path):
    facts = _measured(tmp_path, {"highestElevationMetres": 6190})
    assert facts["highestElevationMetres"] == 6190
    assert facts["lowestElevationMetres"] == 70
    assert facts["elevationNote"] == "Lowest point measured by Unigrids from USGS 3DEP"


def test_a_published_low_point_leaves_only_the_summit_measured(tmp_path):
    facts = _measured(tmp_path, {"lowestElevationMetres": 0})
    assert facts["highestElevationMetres"] == 6178
    assert facts["elevationNote"] == "Highest point measured by Unigrids from USGS 3DEP"


def test_a_range_measured_whole_says_so(tmp_path):
    facts = _measured(tmp_path, {})
    assert (facts["lowestElevationMetres"], facts["highestElevationMetres"]) == (70, 6178)
    assert facts["elevationNote"] == park_elevation.NOTE


def test_a_published_range_carries_no_measurement_note(tmp_path):
    facts = _measured(tmp_path, {"lowestElevationMetres": 70, "highestElevationMetres": 6190})
    assert "elevationNote" not in facts


# MARK: - Climate


def _daily(years=(2024, 2025), rain=lambda day: 2.0, **extra) -> dict:
    days = []
    day = date(years[0], 1, 1)
    while day.year <= years[-1]:
        days.append(day)
        day += timedelta(days=1)
    return {
        "time": [d.isoformat() for d in days],
        "temperature_2m_max": [10.0] * len(days),
        "temperature_2m_min": [0.0] * len(days),
        "precipitation_sum": [rain(d) for d in days],
        **extra,
    }


def test_monthly_precipitation_is_the_mean_monthly_total():
    months = climate._monthly(_daily())
    assert months is not None
    assert months[0] == [10.0, 0.0, 62.0]
    assert months[1] == [10.0, 0.0, round((2 * 29 + 2 * 28) / 2, 1)]


def test_a_missing_day_is_not_a_dry_one():
    # 3 March 2024 unmeasured: that March is left out, not counted 2 mm short, and the
    # mean is 2025's alone.
    months = climate._monthly(_daily(rain=lambda d: None if d == date(2024, 3, 3) else 2.0))
    assert months is not None
    assert months[2][2] == 62.0


def test_precipitation_missing_for_a_whole_month_leaves_no_table():
    months = climate._monthly(_daily(rain=lambda d: None if d.month == 7 else 2.0))
    assert months is None


def test_a_response_with_no_precipitation_leaves_no_table():
    daily = _daily()
    del daily["precipitation_sum"]
    assert climate._monthly(daily) is None
