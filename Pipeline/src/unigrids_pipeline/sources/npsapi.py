"""The NPS Data API (``developer.nps.gov``), for the reference dataset.

What it supplies is the National Park Service's own published record of each unit: the
name and designation, the official description, entrance fees, operating hours, the
weather and directions notes, visitor centres, passport stamp locations, places and
campgrounds, and a set of photographs with their credits. That text is a US government
work and public domain, which is why the guides can adapt it (``SPECIFICATION.md`` §6).

Two habits matter here beyond the shared client's:

* **The key goes in a header, never in a parameter.** Parameters are copied into
  ``source.json`` so the raw store remembers what was asked for; a key in there would end
  up in a file that is one ``git add -f`` away from a commit (``AGENTS.md`` §5).
* **Page in large requests.** The key is rate-limited per hour and is the same one the
  app ships with, so a full reference fetch is a few dozen requests, not a few thousand.
"""

from __future__ import annotations

from typing import Any

import httpx

from . import http

BASE_URL = "https://developer.nps.gov/api/v1"

TERMS = {
    "identifier": "nps-api",
    "title": "NPS Data API",
    "url": BASE_URL,
    "licence": "US government work, public domain; photographs carry their own credits",
    "attribution": "Park information: National Park Service",
    "notes": (
        "Descriptions, fees, hours, visitor centres, stamp locations, places, campgrounds "
        "and photographs. Only photographs credited to the NPS are treated as public "
        "domain; anything credited to someone else is left out of the app."
    ),
}

# The endpoints the reference build reads, and how many rows to ask for per page. The API
# accepts large pages; asking for them is what keeps the request count low.
ENDPOINTS = {
    "parks": 100,
    "visitorcenters": 200,
    "passportstamplocations": 300,
    "places": 300,
    "campgrounds": 200,
}


def keyed_client(api_key: str) -> httpx.Client:
    """The shared client, carrying the key as ``X-Api-Key``."""
    session = http.client()
    session.headers["X-Api-Key"] = api_key
    return session


def fetch_all(
    session: httpx.Client,
    endpoint: str,
    *,
    park_codes: list[str] | None = None,
    park_code: str | None = None,
    record: Any = None,
) -> list[dict[str, Any]]:
    """Every row an endpoint has, optionally limited to some park codes, across pages.

    Park codes are asked for one at a time. The API documents a comma-separated list, but
    the comma arrives percent-encoded from any well-behaved client and the API then
    answers for the first code only — silently, with a 200.
    """
    if park_code:
        return _pages(session, endpoint, park_code=park_code, record=record)
    if park_codes:
        return [
            row
            for code in park_codes
            for row in fetch_all(session, endpoint, park_code=code, record=record)
        ]
    return _pages(session, endpoint, park_code=None, record=record)


def _pages(
    session: httpx.Client, endpoint: str, *, park_code: str | None, record: Any
) -> list[dict[str, Any]]:
    page_size = ENDPOINTS.get(endpoint, 100)
    rows: list[dict[str, Any]] = []
    start = 0
    while True:
        parameters: dict[str, Any] = {"limit": page_size, "start": start}
        if park_code:
            parameters["parkCode"] = park_code.lower()
        response = http.get(
            session, f"{BASE_URL}/{endpoint}", params=parameters, expect="application/json"
        )
        payload = response.json()
        if record is not None:
            record.add_request(f"{BASE_URL}/{endpoint}", parameters)
        page = payload.get("data") or []
        rows.extend(page)
        total = int(payload.get("total") or 0)
        start += len(page)
        if not page or start >= total:
            return rows
