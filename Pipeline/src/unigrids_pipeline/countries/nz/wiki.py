"""Wikidata, Wikipedia and Commons for New Zealand's places: which item is which place.

Wikidata keeps no DOC identifier for New Zealand's parks, so a place is matched to its item
by name and location together: the item's English or Māori label, reduced as Norway's are
(``no.wiki.normal_name``), equal to the place's name, and the item's coordinates within
the place's reach. An item whose article names a national park is never a conservation
park's, and an item two places reach describes neither (Norway's rule, ``no.wiki``).

Pure functions over the raw responses, shared by the fetch (which needs the matches to
know which articles and images to ask for) and the build.
"""

from __future__ import annotations

from collections import Counter
from collections.abc import Iterable
from typing import Any

from ..no import wiki as shared

LICENCE = shared.LICENCE
NEAR_KM = 15.0

# Protected areas and parks in New Zealand, with every English and Māori label.
CANDIDATE_QUERY = """SELECT ?item ?label ?article ?image ?commons ?coord WHERE {
  { ?item wdt:P31/wdt:P279* wd:Q473972 . } UNION { ?item wdt:P31/wdt:P279* wd:Q22698 . }
  ?item wdt:P17 wd:Q664 ; wdt:P625 ?coord .
  ?item rdfs:label ?label . FILTER(LANG(?label) IN ("en", "mi"))
  OPTIONAL { ?article schema:about ?item ; schema:isPartOf <https://en.wikipedia.org/> . }
  OPTIONAL { ?item wdt:P18 ?image }
  OPTIONAL { ?item wdt:P373 ?commons }
}"""

candidates = shared.candidates
article_title = shared.article_title
file_name = shared.file_name
lead = shared.lead
distance_km = shared.distance_km


def match(
    name: str,
    centre: tuple[float, float] | None,
    reach_km: float,
    others: list[dict[str, Any]],
) -> dict[str, Any] | None:
    """The one item labelled ``name`` within ``reach_km`` of ``centre``, or None."""
    if centre is None:
        return None
    wanted = shared.normal_name(name)
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
    tier, name, centre, reach_km)``; tier ``np`` or ``cp``."""
    found: dict[str, dict[str, Any]] = {}
    for key, tier, name, centre, reach_km in places:
        item = match(name, centre, reach_km, others)
        if item is None:
            continue
        named = shared.title_tier(article_title(item.get("article")))
        if named is not None and (named != "np") != (tier != "np"):
            continue
        found[key] = item
    claims = Counter(item["qid"] for item in found.values())
    return {key: item for key, item in found.items() if claims[item["qid"]] == 1}
