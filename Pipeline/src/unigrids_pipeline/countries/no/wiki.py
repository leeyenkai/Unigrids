"""Wikidata, Wikipedia and Commons for Norway's places: which item is which place, and
what of it the build may use.

A place is matched to its Wikidata item by the item's Naturbase ID (P1732), which is
Naturvernområder's own ``naturvernId`` — an exact key, no guessing. The few items without
one are matched by name and location together: the name with its designation taken off,
and the item's coordinates within ``NEAR_KM`` of the place. Either way the item gives the
English Wikipedia article (for a lead), its P18 image and its Commons category.

An item is a place's only when it is no other place's. Wikidata files Møysalen
landscape protection area's Naturbase ID on Møysalen National Park's item, so a match by
ID alone handed the landscape the park's article. An item whose article names another
kind of place, or that two places reach, describes neither (``own_matches``).

These are pure functions over the raw responses, shared by the fetch (which needs the
matches to know which articles and images to ask for) and the build.
"""

from __future__ import annotations

import math
import re
from collections import Counter
from collections.abc import Iterable
from typing import Any
from urllib.parse import unquote

from ... import ids
from . import rules

NEAR_KM = 15.0
LICENCE = "CC BY-SA 4.0"

# The longest lead a card shows, as the US build trims Wikipedia leads.
MAX_SENTENCES = 3
MAX_CHARACTERS = 620

_ENGLISH_DESIGNATION = re.compile(
    r"\s+(?:national park|nature reserve|landscape protection area|protected landscape"
    r"|bird (?:sanctuary|reserve)|protected area)\b.*$",
    re.IGNORECASE,
)


# The kind of place a title names, by Naturvernområder tier, in English or Norwegian.
_TITLE_TIERS = (
    ("np", re.compile(r"\b(?:national park|nasjonalpark)", re.IGNORECASE)),
    ("lvo", re.compile(
        r"\b(?:landscape (?:protection|conservation) area|protected landscape"
        r"|landskapsvernområde)",
        re.IGNORECASE,
    )),
    ("nr", re.compile(
        r"\b(?:nature reserve|bird (?:sanctuary|reserve)|naturreservat|fuglefredningsområde)",
        re.IGNORECASE,
    )),
)


def _value(binding: dict[str, Any], key: str) -> str | None:
    return (binding.get(key) or {}).get("value") or None


def _point(text: str | None) -> tuple[float, float] | None:
    """WDQS's ``Point(lon lat)`` → ``(lat, lon)``."""
    match = re.match(r"Point\(([-\d.eE]+) ([-\d.eE]+)\)", text or "")
    if not match:
        return None
    return float(match.group(2)), float(match.group(1))


def _merge(entry: dict[str, Any], binding: dict[str, Any]) -> None:
    for key in ("article", "image", "commons"):
        if not entry.get(key) and (value := _value(binding, key)):
            entry[key] = value
    if entry.get("coord") is None:
        entry["coord"] = _point(_value(binding, "coord"))


def naturbase_index(bindings: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    """``naturvernId`` → the Wikidata item that carries it as P1732. Where two items
    claim one ID (a park and its old name), the one with an English article wins."""
    items: dict[str, dict[str, Any]] = {}
    claims: dict[str, list[str]] = {}
    for binding in bindings:
        qid = (_value(binding, "item") or "").rsplit("/", 1)[-1]
        naturvern = (_value(binding, "id") or "").strip()
        if not qid or not naturvern:
            continue
        entry = items.setdefault(qid, {"qid": qid, "coord": None})
        _merge(entry, binding)
        if qid not in claims.setdefault(naturvern, []):
            claims[naturvern].append(qid)
    index: dict[str, dict[str, Any]] = {}
    for naturvern, qids in claims.items():
        ranked = sorted(qids, key=lambda q: (not items[q].get("article"), _qid_number(q)))
        index[naturvern] = items[ranked[0]]
    return index


def candidates(bindings: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Norwegian protected-area items without a Naturbase ID, with every label they
    carry, for matching by name and location."""
    items: dict[str, dict[str, Any]] = {}
    for binding in bindings:
        qid = (_value(binding, "item") or "").rsplit("/", 1)[-1]
        if not qid:
            continue
        entry = items.setdefault(qid, {"qid": qid, "coord": None, "names": set()})
        _merge(entry, binding)
        if label := _value(binding, "label"):
            entry["names"].add(normal_name(label))
    return [items[qid] for qid in sorted(items, key=_qid_number)]


def _qid_number(qid: str) -> int:
    digits = re.sub(r"\D", "", qid)
    return int(digits) if digits else 0


def normal_name(name: str) -> str:
    """A name reduced for comparison: designation off, in any of the languages a label
    uses, then slugged."""
    stripped = _ENGLISH_DESIGNATION.sub("", rules.strip_designation(name))
    try:
        return ids.romanised_slug(stripped)
    except ids.UnromanisedNameError:
        return stripped.lower()


def match(
    naturvern_id: str,
    name: str,
    centre: tuple[float, float] | None,
    index: dict[str, dict[str, Any]],
    others: list[dict[str, Any]],
) -> dict[str, Any] | None:
    """The Wikidata item for a place: by Naturbase ID, else by name and location, else
    none. A name match must also be near, and must be the only one."""
    if item := index.get(naturvern_id):
        return item
    if centre is None:
        return None
    wanted = normal_name(name)
    found = [
        item
        for item in others
        if wanted in item["names"]
        and item.get("coord") is not None
        and distance_km(centre, item["coord"]) <= NEAR_KM
    ]
    return found[0] if len(found) == 1 else None


def title_tier(title: str | None) -> str | None:
    """The tier a title's designation names: ``"np"`` for "Møysalen National Park",
    None for a title that names no kind of place ("Maridalen")."""
    for tier, pattern in _TITLE_TIERS:
        if title and pattern.search(title):
            return tier
    return None


def own_matches(
    places: Iterable[tuple[str, str, str, tuple[float, float] | None]],
    index: dict[str, dict[str, Any]],
    others: list[dict[str, Any]],
) -> dict[str, dict[str, Any]]:
    """``naturvernId`` → the Wikidata item that is that place's own, for each of
    ``places`` as ``(naturvernId, tier, name, centre)``.

    ``match`` finds the item. It is refused when its article names another tier — a
    landscape or reserve never takes a national park's article, nor a park a reserve's —
    and when it is matched to two places, as it can describe only one of them. The
    national parks are best included, so an item that is a park's is never a
    neighbour's."""
    found: dict[str, dict[str, Any]] = {}
    for naturvern_id, tier, name, centre in places:
        item = match(naturvern_id, name, centre, index, others)
        if item is None:
            continue
        if title_tier(article_title(item.get("article"))) not in (None, tier):
            continue
        found[naturvern_id] = item
    claims = Counter(item["qid"] for item in found.values())
    return {key: item for key, item in found.items() if claims[item["qid"]] == 1}


def distance_km(a: tuple[float, float], b: tuple[float, float]) -> float:
    (lat1, lon1), (lat2, lon2) = a, b
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi, dlambda = phi2 - phi1, math.radians(lon2 - lon1)
    h = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2
    return 2 * 6371.0088 * math.asin(min(1.0, math.sqrt(h)))


def article_title(url: str | None) -> str | None:
    """``https://en.wikipedia.org/wiki/Forlandet_National_Park`` → ``Forlandet National
    Park``."""
    if not url or "/wiki/" not in url:
        return None
    return unquote(url.rsplit("/wiki/", 1)[1]).replace("_", " ") or None


def file_name(image_url: str | None) -> str | None:
    """A P18 value (``…/Special:FilePath/Prins-karls-forrland%20pho.jpg``) → the Commons
    file name, ``Prins-karls-forrland pho.jpg``."""
    if not image_url:
        return None
    return unquote(image_url.rsplit("/", 1)[-1]).replace("_", " ") or None


def lead(extract: str) -> str:
    """The first sentences of a Wikipedia lead, short enough for a map card."""
    text = re.sub(r"\s+", " ", extract).strip()
    # Pronunciation and native-name parentheticals add nothing on a card.
    text = re.sub(r"\s*\((?:[^()]*?(?:/|listen|pronounced|IPA)[^()]*?)\)", "", text)
    sentences = re.split(r"(?<=[.!?])\s+(?=[A-Z0-9“\"])", text)
    chosen: list[str] = []
    for sentence in sentences:
        if chosen and (
            len(chosen) == MAX_SENTENCES or len(" ".join([*chosen, sentence])) > MAX_CHARACTERS
        ):
            break
        chosen.append(sentence)
    return " ".join(chosen).strip()
