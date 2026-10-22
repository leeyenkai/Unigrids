"""Monthly visitation for every NPS unit, from the NPS's own visitor use statistics.

The best-time-to-visit question has two halves (``SPECIFICATION.md`` §10): what the
weather is like, which the climate panel answers, and how busy it is, which this does.
The source is the NPS Visitor Use Statistics data package on data.gov — every unit's
monthly recreation visits since 1979, released CC0 — read once and reduced to two
things per unit:

* the **mean recreation visits in each calendar month** over ``YEARS``, the most recent
  full years after the pandemic dip, so a month's bar is a normal year's month; and
* the **total for the latest full year**, the figure "annual visits" means elsewhere.

Every figure is the NPS's count averaged, nothing estimated: a unit missing a month in
any of the years has no monthly figures rather than a guessed one.
"""

from __future__ import annotations

import csv
from pathlib import Path
from typing import Any

from . import rawstore
from .rawstore import FetchRecord, SourceTerms
from .sources import http

URL = "https://irma.nps.gov/DataStore/DownloadFile/756959?Reference=2317666"
SOURCE = "visitation"
FILE = "Main_Data.csv"
RECREATION_VISITS = "TRV"
YEARS = (2022, 2023, 2024, 2025)
ANNUAL_YEAR = 2025

TERMS = SourceTerms(
    identifier="nps-visitor-use-statistics",
    title="NPS Visitor Use Statistics data package 2025 (Main_Data.csv, 1979–2025)",
    url="https://catalog.data.gov/dataset/nps-visitor-use-statistics-data-package-2025",
    licence="CC0 1.0 (public domain dedication)",
    attribution="Visitation: National Park Service Visitor Use Statistics",
    notes="Monthly recreation visits (TRV) per unit; reduced to a 2022–2025 monthly mean.",
)


def fetch(version: str, *, refresh: bool = False) -> Path:
    directory = rawstore.version_directory(SOURCE, version)
    path = directory / FILE
    if path.exists() and not refresh:
        print("    visitation: already fetched today")
        return directory
    record = FetchRecord(source=TERMS, fetched_at=rawstore.utc_now())
    with http.client() as session:
        response = http.get(session, URL)
    path.write_bytes(response.content)
    record.add_request(URL)
    record.add_file(path, root=directory)
    record.write(directory)
    print(f"    visitation: {len(response.content) / 1e6:.0f} MB")
    return directory


def build(directory: Path | None) -> dict[str, dict[str, Any]]:
    """``{UNIT: {"monthly": [12], "years": [first, last], "annual": n, "annualYear": y}}``."""
    if directory is None or not (directory / FILE).exists():
        return {}
    counts: dict[str, dict[tuple[int, int], int]] = {}
    with (directory / FILE).open(newline="", encoding="utf-8-sig") as handle:
        for row in csv.DictReader(handle):
            if row.get("Statistic") != RECREATION_VISITS:
                continue
            year = int(row["Year"])
            if year not in YEARS and year != ANNUAL_YEAR:
                continue
            unit = (row.get("UnitCode") or "").strip().upper()
            try:
                value = int(float(row["Value"]))
            except (TypeError, ValueError):
                continue
            counts.setdefault(unit, {})[(year, int(row["Month"]))] = value
    return {unit: entry for unit, by_month in counts.items() if (entry := reduce(by_month))}


def reduce(by_month: dict[tuple[int, int], int]) -> dict[str, Any] | None:
    """One unit's months reduced to the figures the app shows, or ``None``."""
    entry: dict[str, Any] = {}
    if all((year, month) in by_month for year in YEARS for month in range(1, 13)):
        monthly = [
            round(sum(by_month[(year, month)] for year in YEARS) / len(YEARS))
            for month in range(1, 13)
        ]
        if sum(monthly) > 0:
            entry["monthly"] = monthly
            entry["years"] = [YEARS[0], YEARS[-1]]
    if all((ANNUAL_YEAR, month) in by_month for month in range(1, 13)):
        annual = sum(by_month[(ANNUAL_YEAR, month)] for month in range(1, 13))
        if annual > 0:
            entry["annual"] = annual
            entry["annualYear"] = ANNUAL_YEAR
    return entry or None


def attach(places: list[dict[str, Any]], figures: dict[str, dict[str, Any]]) -> int:
    """Give every NPS place its figures. A national park keeps the annual figure its
    curated facts already carry; a unit without one gains it. Returns how many."""
    attached = 0
    for place in places:
        code = (place.get("npsParkCode") or "").upper()
        entry = figures.get(code)
        if not entry:
            continue
        if "monthly" in entry:
            place["visitation"] = {"monthly": entry["monthly"], "years": entry["years"]}
        facts = place.setdefault("facts", {})
        if "annual" in entry and "annualVisits" not in facts:
            facts["annualVisits"] = entry["annual"]
            facts["annualVisitsYear"] = entry["annualYear"]
        attached += 1
    print(f"    visitation: {attached} NPS places")
    return attached

