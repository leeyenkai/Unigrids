"""Small rules the reference build applies to NPS text and figures."""

from __future__ import annotations

from unigrids_pipeline import reference_build, visitation


def test_dated_notices_are_dropped_and_the_rest_kept():
    text = (
        "***CLOSED as of August 31, 2026*** The centre has exhibits and a film. "
        "Scheduled to open late October 2026. Built in 1936 by the CCC."
    )
    assert reference_build._without_notices(text) == (
        "The centre has exhibits and a film. Built in 1936 by the CCC."
    )
    assert reference_build._without_notices("Closed for 2026.") is None
    assert reference_build._without_notices("Open May 9–October 31, 2025.") is None
    assert reference_build._without_notices("Open daily, 9 to 5.") == "Open daily, 9 to 5."


def test_stamp_labels_lose_stale_status():
    assert reference_build._stamp_label("A.G. Gaston Motel (Temporarily Closed)") == (
        "A.G. Gaston Motel"
    )
    assert reference_build._stamp_label("Fort Museum - Closed for Renovation") == "Fort Museum"
    assert reference_build._stamp_label("Kolb Studio") == "Kolb Studio"


def test_known_source_damage_is_repaired():
    assert reference_build._clean("Pools of ?Ohe?o") == "Pools of ʻOheʻo"


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
