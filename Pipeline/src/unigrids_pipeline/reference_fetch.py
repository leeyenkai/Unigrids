"""Fetching for the bundled reference dataset — the half of ``fetch`` the app's map,
guides and overviews read, as opposed to the offline packs.

Each country fetches its own sources into the date-versioned raw store, with a
``source.json`` beside each recording what was asked for and under which terms. This
module runs them in turn; what the US fetches is listed in ``countries/us/fetching.py``.
"""

from __future__ import annotations

from collections.abc import Sequence

from . import countries


def fetch(*, refresh: bool = False, codes: Sequence[str] = countries.DEFAULT) -> None:
    """Fetch everything the reference build reads for ``codes`` into ``raw/<today>/``."""
    for code in codes:
        country = countries.load(code)
        if len(codes) > 1:
            print(f"    {country.NAME}")
        country.fetch(refresh=refresh)
