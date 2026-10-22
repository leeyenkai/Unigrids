"""Official brochures and maps, found on each NPS unit's own site (``SPECIFICATION.md`` §6).

The NPS publishes no list of its brochures. Each unit's "Maps" page links the PDFs it
offers — the Unigrid brochure, a park map, campground and trail maps — and those links
are not standardised: ``ZionUnigrid.pdf``, ``2025_Yellowstone-Unigrid_Web-508.pdf``,
``grsmmap_2024_reduced_508.pdf``. So this step reads every unit's maps page, keeps the
PDF links with the text they are given there, and checks each one answers before the app
is told about it — the "re-check every brochure link" of §12's package step.

Many units link the NPS cartography site instead of a PDF; for those the app opens the
maps page itself, which is what §6 asks for when no stored link works. Nothing here
copies a brochure: the app fetches each one from the NPS the first time it is opened.
"""

from __future__ import annotations

import html
import json
import re
import time
from pathlib import Path
from typing import Any
from urllib.parse import urljoin

import httpx

from . import rawstore
from .rawstore import FetchRecord, SourceTerms
from .sources import http

# The maps page first: its address is what the app opens when no PDF works. Some parks
# keep their PDFs on a brochures page beside it instead.
PAGES = (
    "https://www.nps.gov/{code}/planyourvisit/maps.htm",
    "https://www.nps.gov/{code}/planyourvisit/brochures.htm",
)
FORMAT = 2
MAX_DOCUMENTS = 8
PAUSE_SECONDS = 0.25

TERMS = SourceTerms(
    identifier="nps-brochures",
    title="Official brochure and map links from each NPS unit's maps page",
    url="https://www.nps.gov/",
    licence="Links only; brochures are NPS publications, fetched by the app from nps.gov",
    attribution="Brochures and maps: National Park Service",
    notes="Each link is checked with a HEAD request; size and type are recorded.",
)

_LINK = re.compile(
    r"<a\b[^>]*?href\s*=\s*([\"'])(.*?)\1[^>]*>(.*?)</a>", re.IGNORECASE | re.DOTALL
)
_TAG = re.compile(r"<[^>]+>")
_BROCHURE = re.compile(
    r"unigrid|brochure|official\s+(park\s+)?map|park\s+map|visitor\s+guide", re.IGNORECASE
)
_MAP = re.compile(r"map", re.I)


def fetch(codes: list[str], version: str, *, refresh: bool = False) -> Path:
    """Read every unit's maps page and check the PDFs it links. Resumable."""
    directory = rawstore.version_directory("brochures", version)
    path = directory / "links.json"
    found: dict[str, Any] = json.loads(path.read_text()) if path.exists() and not refresh else {}
    record = FetchRecord(source=TERMS, fetched_at=rawstore.utc_now())
    with http.client() as session:
        for index, code in enumerate(codes):
            if found.get(code, {}).get("format") == FORMAT:
                continue
            found[code] = _unit(session, code, record)
            if index % 25 == 0:
                path.write_text(json.dumps(found, indent=1))
                print(f"    brochures: {index + 1} of {len(codes)} units read", flush=True)
            time.sleep(PAUSE_SECONDS)
    path.write_text(json.dumps(found, indent=1))
    record.add_file(path, root=directory)
    record.write(directory)
    with_documents = sum(1 for entry in found.values() if entry.get("documents"))
    print(f"    brochures: {with_documents} of {len(found)} units link a working PDF")
    return directory


def _unit(session: httpx.Client, code: str, record: FetchRecord) -> dict[str, Any]:
    main_page: str | None = None
    documents: list[dict[str, Any]] = []
    seen: set[str] = set()
    for template in PAGES:
        page = template.format(code=code.lower())
        try:
            response = session.get(page, follow_redirects=True)
        except httpx.HTTPError:
            continue
        record.add_request(page)
        if response.status_code != 200:
            continue
        main_page = main_page or str(response.url)
        for _, href, text in _LINK.findall(response.text):
            href = html.unescape(href).strip()
            if not href.lower().split("?")[0].endswith(".pdf"):
                continue
            url = urljoin(str(response.url), href)
            if url in seen:
                continue
            seen.add(url)
            title = " ".join(html.unescape(_TAG.sub(" ", text)).split())
            documents.append({"url": url, "title": title or _title_from(url)})
        time.sleep(PAUSE_SECONDS)
    documents = documents[:MAX_DOCUMENTS]
    checked = [doc for doc in (_check(session, doc) for doc in documents) if doc]
    return {"page": main_page, "documents": checked, "format": FORMAT}


def _check(session: httpx.Client, document: dict[str, Any]) -> dict[str, Any] | None:
    try:
        response = session.head(document["url"], follow_redirects=True)
    except httpx.HTTPError:
        return None
    kind = response.headers.get("content-type", "")
    if response.status_code != 200 or "pdf" not in kind.lower():
        return None
    length = response.headers.get("content-length")
    checked = {**document, "url": str(response.url)}
    if length and length.isdigit():
        checked["bytes"] = int(length)
    time.sleep(PAUSE_SECONDS / 2)
    return checked


def _title_from(url: str) -> str:
    stem = url.rsplit("/", 1)[-1].rsplit(".", 1)[0]
    return " ".join(re.split(r"[-_]+", stem)).strip() or "PDF"


def _kind(text: str) -> str:
    if _BROCHURE.search(text):
        return "brochure"
    return "map" if _MAP.search(text) else "other"


def build(raw_dir: Path, places: list[dict[str, Any]]) -> dict[str, Any]:
    """``{place id: {"page": maps page, "documents": [...]}}``, brochure first."""
    path = raw_dir / "links.json"
    if not path.exists():
        return {}
    found = json.loads(path.read_text())
    result: dict[str, Any] = {}
    for place in places:
        code = (place.get("npsParkCode") or "").upper()
        entry = found.get(code)
        if not entry or not entry.get("page"):
            continue
        documents = []
        for document in entry.get("documents") or []:
            text = f"{document['title']} {document['url'].rsplit('/', 1)[-1]}"
            kind = _kind(text)
            documents.append({**document, "kind": kind})
        # The Unigrid first, then park maps, then the rest, each in the page's own order.
        rank = {"brochure": 0, "map": 1, "other": 2}
        documents.sort(
            key=lambda doc: (rank[doc["kind"]], 0 if "unigrid" in doc["url"].lower() else 1)
        )
        result[place["id"]] = {"page": entry["page"], "documents": documents}
    print(
        f"    brochures: {sum(1 for e in result.values() if e['documents'])} places with a PDF, "
        f"{len(result)} with a maps page"
    )
    return result
