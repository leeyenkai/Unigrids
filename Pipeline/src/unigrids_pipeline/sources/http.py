"""The shared HTTP client.

Three habits, all of them about being a well-behaved guest on free public
infrastructure — these are government services and a volunteer-funded OSM endpoint, and
nothing here is urgent:

* a **named user agent**, so an operator can tell who is asking,
* **retry with backoff** on the timeouts and 5xx that a busy Overpass instance hands out
  as a matter of course, and
* **a pause between requests** to one host.

``fetch``'s contract also calls out rate limits specifically, because the NPS key the
pipeline would use is the same one shipped inside the app: the pipeline must not be the
thing that exhausts it.
"""

from __future__ import annotations

import time
from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import httpx

from .. import __version__

USER_AGENT = (
    f"unigrids-pipeline/{__version__} "
    "(https://github.com/leeyenkai/Unigrids; offline dataset builder for the Unigrids app)"
)

RETRY_STATUS = frozenset({429, 500, 502, 503, 504, 509})


class FetchError(RuntimeError):
    """A download that did not succeed after its retries."""


@dataclass(frozen=True)
class Politeness:
    """How hard to lean on one host."""

    attempts: int = 4
    backoff_seconds: float = 3.0
    pause_seconds: float = 0.5
    timeout_seconds: float = 180.0


DEFAULT_POLITENESS = Politeness()


def client(politeness: Politeness = DEFAULT_POLITENESS) -> httpx.Client:
    return httpx.Client(
        headers={"User-Agent": USER_AGENT},
        timeout=politeness.timeout_seconds,
        follow_redirects=True,
    )


def get(
    session: httpx.Client,
    url: str,
    *,
    params: Mapping[str, Any] | None = None,
    politeness: Politeness = DEFAULT_POLITENESS,
    expect: str | None = None,
) -> httpx.Response:
    """GET with retries. ``expect`` is a content-type prefix to insist on.

    A service that answers 200 with an HTML error page — which both ArcGIS and Overpass do
    under load — is treated as a failure worth retrying, not as data.
    """
    return _request(session, "GET", url, params=params, politeness=politeness, expect=expect)


def post(
    session: httpx.Client,
    url: str,
    *,
    data: Mapping[str, Any] | None = None,
    politeness: Politeness = DEFAULT_POLITENESS,
    expect: str | None = None,
) -> httpx.Response:
    return _request(session, "POST", url, data=data, politeness=politeness, expect=expect)


def _request(
    session: httpx.Client,
    method: str,
    url: str,
    *,
    params: Mapping[str, Any] | None = None,
    data: Mapping[str, Any] | None = None,
    politeness: Politeness,
    expect: str | None,
) -> httpx.Response:
    last_problem = "no attempt was made"
    for attempt in range(1, politeness.attempts + 1):
        if attempt > 1:
            time.sleep(politeness.backoff_seconds * 2 ** (attempt - 2))
        try:
            response = session.request(method, url, params=params, data=data)
        except httpx.HTTPError as error:
            last_problem = f"{type(error).__name__}: {error}"
            continue
        if response.status_code in RETRY_STATUS:
            last_problem = f"HTTP {response.status_code}"
            continue
        if response.status_code >= 400:
            raise FetchError(f"{url} answered HTTP {response.status_code}: {response.text[:300]}")
        content_type = response.headers.get("content-type", "")
        if expect and not content_type.startswith(expect):
            last_problem = f"content-type {content_type!r} where {expect!r} was expected"
            continue
        time.sleep(politeness.pause_seconds)
        return response
    raise FetchError(f"{url} failed after {politeness.attempts} attempts ({last_problem})")


def write_bytes(path: Path, payload: bytes) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(payload)
    return path
