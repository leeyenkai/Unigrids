"""Monthly climate for each national park, from the Open-Meteo archive (``SPECIFICATION.md``
§10, "Best time to visit: monthly climate normals").

Ten years of daily ERA5 reanalysis at the park's centre point, averaged by month: the mean
daily high, the mean daily low, and the mean monthly precipitation. Ten years rather than
the thirty a climatologist means by "normals", to keep within Open-Meteo's free daily
allowance, and labelled with its years wherever it is shown. One point stands for a whole
park, which in Yellowstone or Denali spans thousands of metres of elevation, and the app
says so.

Open-Meteo is free for non-commercial use and its data is CC BY 4.0, credited in the app.
"""

from __future__ import annotations

import json
import time
from pathlib import Path
from typing import Any

import httpx

from . import rawstore, reference_content
from .rawstore import FetchRecord, SourceTerms
from .sources import http

ARCHIVE = "https://archive-api.open-meteo.com/v1/archive"
FIRST_YEAR, LAST_YEAR = 2016, 2025
PERIOD = f"{FIRST_YEAR}–{LAST_YEAR}"

TERMS = SourceTerms(
    identifier="open-meteo-climate",
    title=f"Open-Meteo historical weather (ERA5), daily, {PERIOD}, at each park's centre",
    url=ARCHIVE,
    licence="CC BY 4.0; free for non-commercial use",
    attribution="Weather data by Open-Meteo.com (ERA5 reanalysis), CC BY 4.0",
)


def fetch(version: str, *, refresh: bool = False) -> Path:
    directory = rawstore.version_directory("climate", version)
    record = FetchRecord(source=TERMS, fetched_at=rawstore.utc_now())
    with http.client() as session:
        for _, row in reference_content.national_park_rows():
            path = directory / f"{row['id']}.json"
            if path.exists() and not refresh:
                continue
            latitude, longitude = row["centre"]
            parameters = {
                "latitude": f"{latitude:.4f}",
                "longitude": f"{longitude:.4f}",
                "start_date": f"{FIRST_YEAR}-01-01",
                "end_date": f"{LAST_YEAR}-12-31",
                "daily": "temperature_2m_max,temperature_2m_min,precipitation_sum",
                "timezone": "auto",
            }
            payload = _get(session, parameters)
            if payload is None:
                print(f"    climate: {row['id']} failed")
                continue
            path.write_text(json.dumps(payload))
            record.add_request(ARCHIVE, parameters)
            record.add_file(path, root=directory)
            print(f"    climate: {row['id']}", flush=True)
            time.sleep(1.0)
    record.write(directory)
    return directory


def _get(session: httpx.Client, parameters: dict[str, str]) -> dict[str, Any] | None:
    for attempt in range(4):
        try:
            response = session.get(ARCHIVE, params=parameters, timeout=120)
        except httpx.HTTPError:
            response = None
        if response is not None and response.status_code == 200:
            return response.json()
        time.sleep(10 * (attempt + 1))
    return None


def build(raw_dir: Path) -> dict[str, Any]:
    """``{place id: {"period": "2016–2025", "months": [[high, low, precipitation], …]}}``."""
    result: dict[str, Any] = {}
    for path in sorted(raw_dir.glob("*.json")):
        if path.name == "source.json":
            continue
        daily = (json.loads(path.read_text()).get("daily")) or {}
        months = _monthly(daily)
        if months:
            result[path.stem] = {"period": PERIOD, "months": months}
    print(f"    climate: {len(result)} parks")
    return result


def _monthly(daily: dict[str, Any]) -> list[list[float]] | None:
    times = daily.get("time") or []
    highs = daily.get("temperature_2m_max") or []
    lows = daily.get("temperature_2m_min") or []
    rain = daily.get("precipitation_sum") or []
    if not times:
        return None
    high_sum = [0.0] * 12
    low_sum = [0.0] * 12
    counts = [0] * 12
    precipitation: dict[tuple[int, int], float] = {}
    for index, day in enumerate(times):
        year, month = int(day[:4]), int(day[5:7])
        high = highs[index] if index < len(highs) else None
        low = lows[index] if index < len(lows) else None
        if high is not None and low is not None:
            high_sum[month - 1] += high
            low_sum[month - 1] += low
            counts[month - 1] += 1
        value = rain[index] if index < len(rain) else None
        if value is not None:
            precipitation[(year, month)] = precipitation.get((year, month), 0.0) + value
    if not all(counts):
        return None
    years = {year for year, _ in precipitation}
    months = []
    for month in range(12):
        totals = [precipitation.get((year, month + 1), 0.0) for year in years]
        months.append([
            round(high_sum[month] / counts[month], 1),
            round(low_sum[month] / counts[month], 1),
            round(sum(totals) / len(totals), 1) if totals else 0.0,
        ])
    return months
