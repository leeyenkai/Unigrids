"""The contract between the reference build and a country.

The reference build (``reference_build``) is a frame. It asks each selected country for
its share of the dataset, merges the shares, drops what a source marked closed, and writes
the files the app bundles. Everything that depends on a country's agencies, sources and
conventions lives in that country's package under ``countries/``.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Protocol

from .. import ids

Record = dict[str, Any]


@dataclass(frozen=True)
class BuildContext:
    """What the frame hands every country's ``assemble``."""

    online: bool
    """Whether the build may fetch what it can only know once the places exist (the US
    asks Wikipedia about places without prose). Offline, a country reads what an earlier
    run cached."""
    images_dir: Path
    """Where bundled photographs are written, resized. Shared by every country: a
    photograph a guide no longer names is removed by the frame, not by its country."""


@dataclass
class Contribution:
    """One country's share of each file the build writes.

    A country fills what it has. ``None`` for a layer means the country built none this
    run, because its raw data is missing; the frame then leaves that file as it is unless
    another country supplies one. An empty value is a layer built and found empty.
    """

    places: list[Record] = field(default_factory=list)
    pois: list[Record] = field(default_factory=list)
    boundaries: dict[str, Record] = field(default_factory=dict)
    """Place ID → encoded outline."""
    routes: dict[str, Record] = field(default_factory=dict)
    """Place ID → a route's line, for places that are roads (scenic byways)."""
    guides: dict[str, Record] = field(default_factory=dict)
    """Place ID → Unigrid guide."""
    transport: dict[str, list[Record]] | None = None
    """Layer name → its lines or stations."""
    trails: list[Record] | None = None
    documents: dict[str, Record] | None = None
    """Place ID → official documents (``brochures.json``)."""
    climate: dict[str, Record] | None = None
    """Place ID → monthly normals."""
    expects_summary: set[str] = field(default_factory=set)
    """Places the country means to carry prose: the build reports any left without it."""
    registries: list[ids.Registry] = field(default_factory=list)
    """Identifier registries the country resolved through. The frame saves them once
    everything is written, so a failed build does not pin identifiers it never shipped."""


class Country(Protocol):
    """A country's package — ``countries/us/__init__.py`` — seen as one object."""

    CODE: str
    """Lower-case ISO 3166-1 alpha-2: ``us``, ``jp``, ``no``. Countries added after the
    US also prefix their place identifiers with it (``ids.country_place_id``)."""
    NAME: str

    def fetch(self, *, refresh: bool) -> Path:
        """Download every source the country's ``assemble`` reads into the raw store,
        resuming where an earlier run stopped. Returns the version directory."""
        ...

    def assemble(self, context: BuildContext) -> Contribution:
        """The country's places, outlines, guides and layers, from the raw store and
        ``content/``. Each place leaves here complete: located, zoned and regioned."""
        ...

    def manifest_note(self, places: list[Record]) -> str:
        """What the manifest says about this country's part of the dataset, given its
        places as shipped."""
        ...
