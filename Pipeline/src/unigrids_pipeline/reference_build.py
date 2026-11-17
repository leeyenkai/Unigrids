"""Build the reference dataset the app bundles, from the raw store and ``content/``.

Writes, into ``UnigridsReference/Resources/reference/``:

``manifest.json``     what this dataset is, when it was built, and from what
``places.json``       national parks, other NPS units, state parks and federal sites
``pois.json``         sights, visitor centres, stamp locations and campgrounds
``themes.json``       theme tags
``guides/np-*.json``  one Unigrid guide per national park
``boundaries.json``   every outline, as encoded polylines
``boundaries-overview.json``  the same outlines generalised for country scale
``routes.json``       every scenic byway's line (``lands_build``)
``transport.json``    Interstates, US routes, Amtrak routes and stations (``lands_build``)
``trails.json``       every national park trail, measured (``trail_catalogue``)
``brochures.json``    each NPS unit's official PDFs and maps page (``brochures``)
``climate.json``      monthly climate at each national park (``climate``)
``emblems.json``      the stamps' pictures, drawn in ``content/emblems/`` (``emblems``)
``images/``           each national park's photographs, resized

This module is the frame. Each country named on the command line assembles its own share
(``countries/``; the US's is ``countries/us/``). The frame merges the shares in the order
the countries were named, drops places a source marked closed, removes photographs and
guides nothing names any more, and writes the files. Nothing here invents a figure. A
value the sources do not carry is left out, and the app renders it as absent.
"""

from __future__ import annotations

import json
import os
from collections import Counter
from collections.abc import Sequence
from datetime import UTC, date, datetime
from typing import Any

from . import config, countries, emblems, outline, reference_content
from .countries import BuildContext, Contribution
from .countries.common import encode_outline

OUT = config.REFERENCE_DIR


def build(*, online: bool = False, codes: Sequence[str] = countries.DEFAULT) -> None:
    """Build the dataset for the countries ``codes`` names, and only those. ``online``
    lets a country fetch what it can only know once its places exist; offline, it reads
    what an earlier run cached."""
    selected = [countries.load(code) for code in codes]

    # Photographs are rebuilt in place rather than wiped: a resized copy whose raw original
    # has since been cleared from the raw store (they are large) is kept as it is.
    images_dir = OUT / "images"
    images_dir.mkdir(parents=True, exist_ok=True)
    # Guides are rewritten in place and only stale ones removed, never the folder wiped
    # and refilled: in an iCloud-synced checkout, deleting and recreating files that are
    # still uploading leaves "np-zion 2.json" conflict copies, which would ship.
    guides_dir = OUT / "guides"
    guides_dir.mkdir(parents=True, exist_ok=True)

    context = BuildContext(online=online, images_dir=images_dir)
    shares = []
    for country in selected:
        if len(selected) > 1:
            print(f"    {country.NAME}")
        shares.append((country, country.assemble(context)))
    merged = merge([share for _, share in shares])

    places, boundaries, routes, guides = (
        merged.places, merged.boundaries, merged.routes, merged.guides
    )
    closed = {place["id"] for place in places if place.pop("closed", False)}
    if closed:
        places = [place for place in places if place["id"] not in closed]
        for place_id in closed:
            boundaries.pop(place_id, None)
            routes.pop(place_id, None)

    written_images = {
        image["assetName"]
        for guide in guides.values()
        for image in [guide.get("hero"), *guide.get("gallery", [])]
        if image and image.get("assetName")
    }
    for stale in images_dir.iterdir():
        if stale.name not in written_images:
            stale.unlink()

    notes = [
        country.manifest_note([place for place in share.places if place["id"] not in closed])
        for country, share in shares
    ]
    if len(notes) > 1:
        # Each country's note says which country it describes; the US's predates others.
        notes = [
            note if note.startswith(f"{country.NAME}:") else f"{country.NAME}: {note}"
            for (country, _), note in zip(shares, notes, strict=True)
        ]
    drawn = emblems.load()
    undrawn = emblems.attach(places, drawn)
    _write("manifest", _manifest(notes, countries=len(notes)))
    _write("places", places)
    _write("pois", merged.pois)
    _write("themes", reference_content.themes())
    _write("boundaries", boundaries, compact=True)
    _write("boundaries-overview", _overview_outlines(boundaries), compact=True)
    _write("routes", routes, compact=True)
    if merged.transport is not None:
        _write("transport", merged.transport, compact=True)
    if merged.trails is not None:
        _write("trails", merged.trails, compact=True)
    if merged.documents is not None:
        _write("brochures", merged.documents, compact=True)
    if merged.climate is not None:
        _write("climate", merged.climate, compact=True)
    _write("emblems", drawn, compact=True)
    for place_id, guide in guides.items():
        _write(f"guides/{place_id}", guide)
    for stale in guides_dir.glob("*.json"):
        if stale.stem not in guides:
            stale.unlink()
    for registry in merged.registries:
        registry.save()
        if registry.added:
            print(f"    identifiers: {registry.added} new, recorded in {registry.path.name}")

    image_bytes = sum(path.stat().st_size for path in images_dir.iterdir())
    outline_bytes = (OUT / "boundaries.json").stat().st_size
    tiers: dict[str, int] = {}
    for place in places:
        tiers[place["kind"]] = tiers.get(place["kind"], 0) + 1
    print(f"    places: {len(places)} {tiers}")
    print(f"    points of interest: {len(merged.pois)}")
    print(f"    stamp pictures: {len(drawn)}; national parks still on a motif: {len(undrawn)}")
    print(f"    outlines: {len(boundaries)}, {outline_bytes / 1e6:.2f} MB")
    print(f"    photographs: {len(list(images_dir.iterdir()))}, {image_bytes / 1e6:.1f} MB")
    written = sum(1 for guide in guides.values() if guide.get("story"))
    print(f"    guides with written content: {written} of {len(guides)}")
    unwritten = [
        place["id"]
        for place in places
        if place.get("summary") is None and place["id"] in merged.expects_summary
    ]
    if unwritten:
        print(f"    places without a summary: {', '.join(unwritten)}")


def merge(shares: Sequence[Contribution]) -> Contribution:
    """The countries' shares as one dataset, in the order given.

    Two countries claiming one place, outline, route, guide, document set or climate table
    is a build error, never a silent overwrite: an identifier in a user's log must name
    one thing. Transport layers of the same name are joined.
    """
    merged = Contribution()
    place_owner: dict[str, int] = {}
    for index, share in enumerate(shares):
        for place in share.places:
            if place_owner.setdefault(place["id"], index) != index:
                raise ValueError(f"place {place['id']!r} is built by two countries")
        merged.places.extend(share.places)
        merged.pois.extend(share.pois)
        _join(merged.boundaries, share.boundaries, "boundaries")
        _join(merged.routes, share.routes, "routes")
        _join(merged.guides, share.guides, "guides")
        if share.transport is not None:
            if merged.transport is None:
                merged.transport = {}
            for layer, rows in share.transport.items():
                merged.transport.setdefault(layer, []).extend(rows)
        if share.trails is not None:
            merged.trails = [*(merged.trails or []), *share.trails]
        if share.documents is not None:
            if merged.documents is None:
                merged.documents = {}
            _join(merged.documents, share.documents, "brochures")
        if share.climate is not None:
            if merged.climate is None:
                merged.climate = {}
            _join(merged.climate, share.climate, "climate")
        merged.expects_summary |= share.expects_summary
        merged.registries.extend(share.registries)
    # A point of interest is named in a log by its identifier alone, so it must name one.
    counts = Counter(poi["id"] for poi in merged.pois)
    if shared := sorted(identifier for identifier, count in counts.items() if count > 1):
        raise ValueError(f"points of interest share an identifier: {', '.join(shared[:5])}")
    return merged


def _join(whole: dict[str, Any], part: dict[str, Any], name: str) -> None:
    if clash := whole.keys() & part.keys():
        listed = ", ".join(sorted(clash)[:5])
        raise ValueError(f"{name}: {listed} built by two countries")
    whole.update(part)


# The country-scale outlines, in degrees: about 900 m. Drawn when the whole Lower 48 is
# on screen, where a pixel is several kilometres, so nothing finer would show; a speck that
# vanishes at this tolerance leaves its pin to stand for it.
OVERVIEW_TOLERANCE = 0.008


def _overview_outlines(boundaries: dict[str, Any]) -> dict[str, Any]:
    """Every outline again, generalised for the map at country scale.

    Fourteen hundred outlines at full detail are a quarter of a million vertices: more
    than the map should draw for a view where none of that detail is visible. This set is
    a tenth of the size, and the map swaps to the full one as the camera comes in.
    """
    overview: dict[str, Any] = {}
    for place_id, entry in boundaries.items():
        polygons = [[outline.decode(ring) for ring in polygon] for polygon in entry["polygons"]]
        coarse = encode_outline(polygons, OVERVIEW_TOLERANCE)
        if coarse:
            overview[place_id] = coarse
    return overview


# MARK: - Output


def build_date() -> date:
    """Today, or the day ``SOURCE_DATE_EPOCH`` names. That is the reproducible-builds
    convention, and the golden check (``scripts/golden.sh``) uses it so a rebuild on
    another day writes the same manifest."""
    if epoch := os.environ.get("SOURCE_DATE_EPOCH"):
        return datetime.fromtimestamp(int(epoch), UTC).date()
    return date.today()


def _manifest(notes: list[str], *, countries: int = 1) -> dict[str, Any]:
    return {
        # 4: every state park, Wikipedia leads, visitation, time zones, OSM trails.
        # 5: countries beyond the US — subdivisions, local names, quasi-national parks,
        # protected landscapes and nature reserves (ADR 0013). A US-only build stays at 4,
        # so the golden check of the US data still holds byte for byte.
        "version": 5 if countries > 1 else 4,
        "builtOn": build_date().isoformat(),
        "provenance": "pipeline",
        "note": " ".join(notes),
    }


def _write(name: str, payload: Any, *, compact: bool = False) -> None:
    path = OUT / f"{name}.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    if compact:
        text = json.dumps(payload, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
    else:
        text = json.dumps(payload, ensure_ascii=False, indent=1)
    # Unchanged bytes are not rewritten, for the same reason as the guides above.
    if path.exists() and path.read_text() == text + "\n":
        return
    path.write_text(text + "\n")
