"""Stable Unigrids identifiers.

User records point at reference data **only** by these identifiers, because the dataset
is replaced wholesale with each app release (``AGENTS.md`` §4). So the one rule that
matters here is that an identifier for a given real-world thing must not change between
runs — not when a name is corrected, not when a source reorders its rows, not when a
coordinate is refined.

That is why identifiers are derived from a source's own stable key (an NPS park code, a
PAD-US unit id) rather than from a name or a position, and why ``match`` keeps the
mapping rather than recomputing it.
"""

from __future__ import annotations

import re
import unicodedata

_SEPARATORS = re.compile(r"[^a-z0-9]+")

# Dash-like and path characters become word separators. Folding to ASCII would otherwise
# *delete* an en dash, turning "Wrangell–St. Elias" into "wrangellst-elias".
_TO_HYPHEN = str.maketrans(dict.fromkeys("\u2010\u2011\u2012\u2013\u2014\u2015/\\", "-"))

# Apostrophes vanish rather than separating, so "Hawaiʻi" gives "hawaii" and not
# "hawai-i". Includes the ʻokina, which NPS park names use.
_TO_NOTHING = str.maketrans(dict.fromkeys("'\u2018\u2019\u02bb\u02bc\u0060\u00b4", ""))


def slug(text: str) -> str:
    """A lowercase, hyphenated slug.

    Diacritics fold to ASCII so ``Haleakalā`` and ``Haleakala`` produce the same slug,
    which keeps an identifier stable when a source corrects its spelling.
    """
    cleaned = text.translate(_TO_NOTHING).translate(_TO_HYPHEN)
    folded = unicodedata.normalize("NFKD", cleaned)
    ascii_text = folded.encode("ascii", "ignore").decode("ascii").lower()
    return _SEPARATORS.sub("-", ascii_text).strip("-")


def place_id(kind: str, name: str) -> str:
    """``np-zion``, ``nm-bears-ears``, ``sp-valley-of-fire``."""
    return f"{kind}-{slug(name)}"


def poi_id(place_slug: str, name: str) -> str:
    """``poi-zion-angels-landing``."""
    return f"poi-{place_slug}-{slug(name)}"


def trail_id(place_slug: str, name: str) -> str:
    """``trail-zion-narrows-bottom-up``."""
    return f"trail-{place_slug}-{slug(name)}"


def theme_id(name: str) -> str:
    """``theme-volcanoes``."""
    return f"theme-{slug(name)}"
