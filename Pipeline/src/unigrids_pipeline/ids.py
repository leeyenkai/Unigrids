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

from . import config

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


# MARK: - Countries after the US
#
# ``slug`` deletes whatever it cannot fold to ASCII. For English names that is harmless,
# and the US's identifiers built with it are in users' logs, so it stays exactly as it
# is. For Norwegian, Sámi and Japanese names it is destructive — "Færder" becomes
# "frder", "知床" becomes nothing — so the countries added after the US slug through
# ``romanised_slug`` instead, and carry their country in every identifier.

# Letters the Norwegian and Sámi alphabets use that Unicode does not decompose into a
# base letter and a mark. The rest — å, á, č, š, ž, ï, and the macrons of romanised
# Japanese (Chūbu) — do decompose, and lose their marks as ``slug`` folds Haleakalā.
_TRANSLITERATION = str.maketrans({
    "æ": "ae", "Æ": "ae",
    "ø": "o", "Ø": "o",
    "đ": "d", "Đ": "d",
    "ŋ": "n", "Ŋ": "n",
    "ŧ": "t", "Ŧ": "t",
    # Canada's Dene, Tlingit and Salish orthographies: the barred l, the glottal stop and
    # labialisation ("Nàłùdäy", "Saoyú-Ɂehdacho", "Nahʔą Dehé", "Mᑫuqʷin").
    "ł": "l", "Ł": "l",
    "ɂ": "", "Ɂ": "", "ʔ": "",
    "ʷ": "w",
})

# Each country's place namespaces: ``<country>-<tier>-<slug>``.
PLACE_NAMESPACES: dict[str, tuple[str, ...]] = {
    # 国立公園 national parks and 国定公園 quasi-national parks.
    "jp": ("np", "qnp"),
    # Nasjonalparker, landskapsvernområder and naturreservater.
    "no": ("np", "lvo", "nr"),
    # National parks, and conservation and forest parks (Conservation Act s 19).
    "nz": ("np", "cp"),
    # The national parks with a guide, and every other state or territory national park.
    "au": ("np", "snp"),
    # National parks (with the reserves and Rouge National Urban Park), national marine
    # conservation areas, and provincial and territorial parks.
    "ca": ("np", "mca", "pp"),
}

REGISTRY_KINDS = ("places", "pois", "trails")


class UnromanisedNameError(ValueError):
    """A name that cannot become a slug without losing letters, or that has none."""


def romanised_slug(text: str) -> str:
    """A slug for a name in the Latin alphabet but not in English: Norwegian, Sámi, or
    Japanese as officially romanised (``Chūbu-Sangaku`` → ``chubu-sangaku``).

    Letters that need it are transliterated (æ → ae, ø → o, đ ŋ ŧ → d n t), marks are
    dropped, and anything that is neither a letter nor a digit separates words. A letter
    still outside ASCII after that — kanji, kana, a letter the table does not know — is
    refused rather than deleted, so it fails the build instead of shipping a truncated
    identifier. So is a name that leaves nothing to slug.
    """
    cleaned = text.translate(_TO_NOTHING).translate(_TO_HYPHEN).translate(_TRANSLITERATION)
    kept: list[str] = []
    unknown: set[str] = set()
    for character in unicodedata.normalize("NFKD", cleaned):
        category = unicodedata.category(character)
        if character.isascii():
            kept.append(character)
        elif category == "Mn":
            continue
        elif category[0] in "LN":
            unknown.add(character)
        else:
            kept.append("-")
    if unknown:
        raise UnromanisedNameError(
            f"{text!r}: no Latin form for {' '.join(sorted(unknown))}; give its romanised name"
        )
    result = _SEPARATORS.sub("-", "".join(kept).lower()).strip("-")
    if not result:
        raise UnromanisedNameError(f"{text!r} has no letters or digits to make a slug from")
    return result


def country_place_id(country: str, tier: str, name: str) -> str:
    """``jp-np-shiretoko``, ``no-lvo-…``: the identifier proposed for a place abroad.

    National parks are few and curated, and keep the identifier their content file gives
    them. Every other place abroad resolves its proposal through
    ``country_registry(country, "places")``, keyed on the source's own identifier, so a
    renamed record keeps its identifier.
    """
    if tier not in PLACE_NAMESPACES.get(country, ()):
        raise ValueError(f"no place namespace {country!r}-{tier!r}")
    return f"{country}-{tier}-{romanised_slug(name)}"


def country_poi_id(
    registry: Registry, country: str, park_slug: str, key: str, name: str | None
) -> str:
    """``poi-jp-<park>-<slug>``: a point of interest abroad, pinned to its source's own
    identifier (``key``, as ``"osm:node/123"``) in the country's registry."""
    return _resolve_abroad(registry, "poi", country, park_slug, key, name)


def country_trail_id(
    registry: Registry, country: str, park_slug: str, key: str, name: str | None
) -> str:
    """``trail-no-<park>-<slug>``: a trail abroad, pinned to its source's own identifier
    (``key``, as ``"turrutebasen:1234"``) in the country's registry."""
    return _resolve_abroad(registry, "trail", country, park_slug, key, name)


def _resolve_abroad(
    registry: Registry, kind: str, country: str, park_slug: str, key: str, name: str | None
) -> str:
    if country not in PLACE_NAMESPACES:
        raise ValueError(f"no country namespace {country!r}")
    source, _, local = key.partition(":")
    if not source or not local:
        raise ValueError(f"{key!r}: a registry key is '<source>:<the source's own id>'")
    # A name with no Latin form (a hut OSM knows only as 槍ヶ岳山荘) is named by its
    # source key instead. The identifier is still stable, because the registry pins it.
    try:
        stem = romanised_slug(name or "")
    except UnromanisedNameError:
        stem = romanised_slug(key)
    return registry.resolve(key, f"{kind}-{country}-{romanised_slug(park_slug)}-{stem}")


def country_registry(country: str, kind: str) -> Registry:
    """The committed registry of one country's places, points of interest or trails:
    ``content/ids/<country>/<kind>.json``. The US's places keep ``content/ids/places.json``,
    and its sights and trails, which predate registries, slug from their names."""
    if country not in PLACE_NAMESPACES:
        raise ValueError(f"no country namespace {country!r}")
    if kind not in REGISTRY_KINDS:
        raise ValueError(f"{kind!r} is not one of {', '.join(REGISTRY_KINDS)}")
    return Registry(config.CONTENT_DIR / "ids" / country / f"{kind}.json")


def country_of(identifier: str) -> str:
    """The country an identifier belongs to, read off its prefix — the rule the app
    applies to a place that has left the dataset. An identifier without a country prefix
    is American, because the US's identifiers predate countries."""
    parts = identifier.split("-", 2)
    candidate = parts[1] if parts[0] in ("poi", "trail") and len(parts) > 1 else parts[0]
    return candidate if candidate in PLACE_NAMESPACES else "us"


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
        base = f"{proposed}-{slug(qualifier)}" if qualifier else proposed
        candidates = [proposed, base] if qualifier else [proposed]
        candidates.extend(f"{base}-{n}" for n in range(2, 100))
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
