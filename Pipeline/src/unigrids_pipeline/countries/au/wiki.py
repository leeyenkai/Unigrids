"""Wikidata, Wikipedia and Commons for Australia's places: which item is which place.

Wikidata keeps no CAPAD identifier, so a place is matched to its item by name and location
together, as New Zealand's and Canada's are: the item's English label with its designation
taken off ("Wollemi National Park" → ``wollemi``) equal to the park's name, and the item's
coordinates within the park's reach. The national parks with a guide are matched with the
rest, so an item that is theirs is never a neighbour's, and an item two places reach
describes neither (Norway's rule, ``no.wiki``).

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

# Protected areas and parks in Australia, with every English label.
CANDIDATE_QUERY = """SELECT ?item ?label ?article ?image ?commons ?coord WHERE {
  { ?item wdt:P31/wdt:P279* wd:Q473972 . } UNION { ?item wdt:P31/wdt:P279* wd:Q22698 . }
  ?item wdt:P17 wd:Q408 ; wdt:P625 ?coord .
  ?item rdfs:label ?label . FILTER(LANG(?label) = "en")
  OPTIONAL { ?article schema:about ?item ; schema:isPartOf <https://en.wikipedia.org/> . }
  OPTIONAL { ?item wdt:P18 ?image }
  OPTIONAL { ?item wdt:P373 ?commons }
}"""

article_title = shared.article_title
file_name = shared.file_name
lead = shared.lead
distance_km = shared.distance_km

_DESIGNATION = re.compile(
    r"\s+national park(?:\s*\((?:aboriginal land|cypal|scientific|limited depth)\))?"
    r"(?:,?\s+(?:new south wales|victoria|queensland|south australia|western australia"
    r"|tasmania|northern territory))?\s*$",
    re.IGNORECASE,
)
# Titles that name a kind of place other than a national park.
_OTHER_KINDS = re.compile(
    r"\b(?:conservation park|state forest|nature reserve|state conservation area"
    r"|regional park|marine park|state park|conservation reserve)\b",
    re.IGNORECASE,
)


def normal_name(name: str) -> str:
    """A name reduced for comparison: its designation off, then slugged. "Wollemi
    National Park" and "Wollemi" agree."""
    text = re.sub(r"\s+", " ", name.replace("’", "'").replace("—", "-")).strip()
    stripped = _DESIGNATION.sub("", text).strip() or text
    try:
        return ids.romanised_slug(stripped)
    except ids.UnromanisedNameError:
        return stripped.lower()


def candidates(bindings: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Australia's protected-area items with every label they carry, reduced for
    matching."""
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
    tier, name, centre, reach_km)``. An item whose article is about a conservation park,
    a forest or a reserve of the same name is not the national park's."""
    found: dict[str, dict[str, Any]] = {}
    for key, _tier, name, centre, reach_km in places:
        item = match(name, centre, reach_km, others)
        if item is None:
            continue
        title = article_title(item.get("article"))
        if title and _OTHER_KINDS.search(title):
            continue
        found[key] = item
    claims = Counter(item["qid"] for item in found.values())
    return {key: item for key, item in found.items() if claims[item["qid"]] == 1}
