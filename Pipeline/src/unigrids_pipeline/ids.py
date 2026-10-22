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

import json
import re
import unicodedata
from pathlib import Path

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


class IdentifierCollisionError(RuntimeError):
    """Two different source records asked for the same identifier and neither can yield."""


class Registry:
    """The committed mapping from a source record's own key to the identifier it was given.

    Deriving an identifier from a name is only stable while the name is. A registry makes
    the first answer permanent: once ``usfs-forest:COCONINO NATIONAL FOREST`` has been
    given ``nf-coconino`` it keeps it when the Forest Service renames the record, and a
    second record that would slug the same way gets a different identifier instead of
    silently replacing — or being dropped in favour of — the first.

    The file is a flat JSON object, sorted, one entry per line, so a build that adds
    places shows up in review as added lines and nothing else.
    """

    def __init__(self, path: Path) -> None:
        self.path = path
        self._by_key: dict[str, str] = (
            json.loads(path.read_text()) if path.exists() else {}
        )
        self._owner: dict[str, str] = {}
        for key, identifier in self._by_key.items():
            if identifier in self._owner:
                raise IdentifierCollisionError(
                    f"{path.name}: {identifier!r} is held by both "
                    f"{self._owner[identifier]!r} and {key!r}"
                )
            self._owner[identifier] = key
        self._added = 0

    def resolve(self, key: str, proposed: str, *, qualifier: str | None = None) -> str:
        """The identifier for ``key``: the one it already has, or ``proposed`` if that is
        free, or ``proposed`` qualified (``-ut``, then ``-2``, ``-3``…) if it is not."""
        if existing := self._by_key.get(key):
            return existing
        candidates = [proposed]
        if qualifier:
            candidates.append(f"{proposed}-{slug(qualifier)}")
        candidates.extend(f"{candidates[-1]}-{n}" for n in range(2, 100))
        for candidate in candidates:
            if candidate not in self._owner:
                self._by_key[key] = candidate
                self._owner[candidate] = key
                self._added += 1
                return candidate
        raise IdentifierCollisionError(f"no free identifier for {key!r} near {proposed!r}")

    def owner(self, identifier: str) -> str | None:
        """The source key an identifier belongs to, if any."""
        return self._owner.get(identifier)

    @property
    def added(self) -> int:
        """How many keys this run gave a first identifier."""
        return self._added

    def save(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        lines = [
            f"  {json.dumps(key, ensure_ascii=False)}: {json.dumps(value)}"
            for key, value in sorted(self._by_key.items())
        ]
        self.path.write_text("{\n" + ",\n".join(lines) + "\n}\n")
