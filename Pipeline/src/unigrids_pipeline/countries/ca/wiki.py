"""Wikidata, Wikipedia and Commons for Canada's places: which item is which place.

Wikidata keeps no CPCAD identifier, so a place is matched to its item by name and location
together, as New Zealand's are: the item's English or French label with its designation
taken off ("Cape Scott Provincial Park", "Parc national de Frontenac" → ``cape-scott``,
``frontenac``) equal to the place's name, and the item's coordinates within the place's
reach. The national parks and marine areas are matched with the provincial parks, so an
item that is theirs is never a neighbour's, and an item two places reach describes
neither (Norway's rule, ``no.wiki``).

Pure functions over the raw responses, shared by the fetch and the build.
"""

from __future__ import annotations

import re
from collections import Counter
from collections.abc import Iterable
from typing import Any

from ... import ids
from ..no import wiki as shared

LICENCE = shared.LICENCE
NEAR_KM = 15.0

# Protected areas and parks in Canada, with every English and French label.
CANDIDATE_QUERY = """SELECT ?item ?label ?article ?image ?commons ?coord WHERE {
  { ?item wdt:P31/wdt:P279* wd:Q473972 . } UNION { ?item wdt:P31/wdt:P279* wd:Q22698 . }
  ?item wdt:P17 wd:Q16 ; wdt:P625 ?coord .
  ?item rdfs:label ?label . FILTER(LANG(?label) IN ("en", "fr"))
  OPTIONAL { ?article schema:about ?item ; schema:isPartOf <https://en.wikipedia.org/> . }
  OPTIONAL { ?item wdt:P18 ?image }
  OPTIONAL { ?item wdt:P373 ?commons }
}"""

article_title = shared.article_title
file_name = shared.file_name
lead = shared.lead
distance_km = shared.distance_km

_DESIGNATIONS = re.compile(
    r"\s+(?:wildland provincial park|provincial wilderness park|wilderness provincial park"
    r"|provincial park(?: and protected area)?|territorial park|wilderness park"
    r"|national park(?: reserve)?(?: of canada)?|national urban park"
    r"|national marine (?:conservation area|park)(?: reserve)?|marine park|park)"
    r"(?:\s*\([^)]*\))?\s*$",
    re.IGNORECASE,
)
_FRENCH = re.compile(
    r"^(?:parc national|parc provincial|parc territorial|parc marin|réserve de parc national"
    r"|aire marine nationale de conservation)(?:\s+du\s+canada)?\s+"
    r"(?:(?:de\s+la|de\s+l'|du|des|de|d')\s*)?",
    re.IGNORECASE,
)

# The kind of place an article's title names, by tier.
_TITLE_TIERS = (
    ("mca", re.compile(r"\bmarine (?:conservation area|park)\b", re.IGNORECASE)),
    ("pp", re.compile(r"\b(?:provincial|territorial) park\b|\(qu[ée]bec\)", re.IGNORECASE)),
    ("np", re.compile(r"\bnational (?:park|urban park)\b", re.IGNORECASE)),
)


def normal_name(name: str) -> str:
    """A name reduced for comparison: its designation off, in English or French, then
    slugged. "Wells Gray Provincial Park" and "Parc provincial Wells Gray" agree."""
    text = re.sub(r"\s+", " ", name.replace("’", "'")).strip()
    text = _FRENCH.sub("", text)
    stripped = _DESIGNATIONS.sub("", text).strip() or text
    try:
        return ids.romanised_slug(stripped)
    except ids.UnromanisedNameError:
        return stripped.lower()


def candidates(bindings: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Canada's protected-area items with every label they carry, reduced for matching."""
    items: dict[str, dict[str, Any]] = {}
    for binding in bindings:
        qid = (shared._value(binding, "item") or "").rsplit("/", 1)[-1]
        if not qid:
            continue
        entry = items.setdefault(qid, {"qid": qid, "coord": None, "names": set()})
        shared._merge(entry, binding)
        if label := shared._value(binding, "label"):
            entry["names"].add(normal_name(label))
    return [items[qid] for qid in sorted(items, key=shared._qid_number)]


def title_tier(title: str | None) -> str | None:
    """``"mca"``, ``"pp"`` or ``"np"`` for a title that names a kind of place, else None.
    Québec's parks are titled "national parks" in English and "(Québec)" says otherwise."""
    for tier, pattern in _TITLE_TIERS:
        if title and pattern.search(title):
            return tier
    return None


def match(
    name: str,
    centre: tuple[float, float] | None,
    reach_km: float,
    others: list[dict[str, Any]],
) -> dict[str, Any] | None:
    """The one item labelled ``name`` within ``reach_km`` of ``centre``, or None."""
    if centre is None:
        return None
    wanted = normal_name(name)
    found = [
        item
        for item in others
        if wanted in item["names"]
        and item.get("coord") is not None
        and distance_km(centre, item["coord"]) <= max(NEAR_KM, reach_km)
    ]
    return found[0] if len(found) == 1 else None


def own_matches(
    places: Iterable[tuple[str, str, str, tuple[float, float] | None, float]],
    others: list[dict[str, Any]],
) -> dict[str, dict[str, Any]]:
    """``key`` → the item that is that place's own, for each of ``places`` as ``(key,
    tier, name, centre, reach_km)``; tier ``np``, ``mca``, ``pp``, or ``ppqc`` for a parc
    national du Québec, whose English article calls it a national park."""
    found: dict[str, dict[str, Any]] = {}
    for key, tier, name, centre, reach_km in places:
        item = match(name, centre, reach_km, others)
        if item is None:
            continue
        named = title_tier(article_title(item.get("article")))
        allowed = {"pp", "np"} if tier == "ppqc" else {tier}
        if named is not None and named not in allowed:
            continue
        found[key] = item
    claims = Counter(item["qid"] for item in found.values())
    return {key: item for key, item in found.items() if claims[item["qid"]] == 1}
