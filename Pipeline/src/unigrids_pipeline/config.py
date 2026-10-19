"""Paths and settings the pipeline steps share."""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

PIPELINE_ROOT = Path(__file__).resolve().parents[2]
REPO_ROOT = PIPELINE_ROOT.parent

# Downloads and intermediates. Gitignored: large, and reproducible from the sources.
RAW_DIR = PIPELINE_ROOT / "raw"
WORK_DIR = PIPELINE_ROOT / "work"
OUT_DIR = PIPELINE_ROOT / "out"

# Hand-written, version-controlled content the `edit` step validates.
CONTENT_DIR = PIPELINE_ROOT / "content"

# Where `package` copies the built dataset. The directory is gitignored — generated data
# belongs to its generator — and the app reads it in place of the hand-authored seed once
# it exists.
APP_RESOURCES = (
    REPO_ROOT / "Packages/UnigridsKit/Sources/UnigridsReference/Resources/generated"
)

# The four parks the pilot proves the template and the pack size on
# (SPECIFICATION.md §16).
PILOT_PARKS = ("ZION", "ACAD", "YELL", "GRSM")


@dataclass(frozen=True)
class Park:
    """A park the pipeline can build a pack for."""

    unit_code: str
    """The NPS park code — the stable key every source is joined on."""
    place_id: str
    """The Unigrids ID the app and the user's log know this place by."""
    slug: str
    """The short form trail and sight IDs are built from (``ids.trail_id``)."""
    name: str


# Keyed by NPS park code. Zion is the pilot's measured park; the other three pilot parks
# build from the same code path once their raw data is fetched.
PARKS = {
    "ZION": Park("ZION", "np-zion", "zion", "Zion National Park"),
    "ACAD": Park("ACAD", "np-acadia", "acadia", "Acadia National Park"),
    "YELL": Park("YELL", "np-yellowstone", "yellowstone", "Yellowstone National Park"),
    "GRSM": Park(
        "GRSM",
        "np-great-smoky-mountains",
        "great-smoky-mountains",
        "Great Smoky Mountains National Park",
    ),
}

DEFAULT_PARK = "ZION"


@dataclass(frozen=True)
class PackSettings:
    """How an offline pack is rendered.

    Every figure here moves the pack's size, which is the pilot's open question
    (``docs/mvp-scope.md``), so each one is a knob the size report can be re-run against
    rather than a constant buried in the renderer.
    """

    min_zoom: int = 10
    """Park-in-its-region. Below this the bundled base map is enough."""
    max_zoom: int = 16
    """About 2 m per pixel at Zion's latitude. The elevation model is 10 m, so the relief
    at this zoom is interpolated — the size report treats dropping it as the first thing
    to trim."""
    tile_size: int = 256
    """What ``MKTileOverlay`` asks for by default."""
    tile_format: str = "webp"
    """``webp``, ``png`` or ``png8`` (256-colour, dithered). WebP is the default because
    the measurement says so: shaded relief is a continuous-tone image, which is the thing
    PNG is worst at, and lossy WebP comes out about eight times smaller at a difference
    the eye cannot find on a map. The report measures all three on the same tiles every
    run, so this stays a decision backed by numbers rather than a default nobody
    revisits. iOS has decoded WebP natively since 14, and the app's floor is far above
    that (``AGENTS.md`` §7)."""
    webp_quality: int = 82
    """Measured against 70, 75 and 90 on Zion's tiles: below about 80 the relief starts
    to band on smooth slopes, above it the bytes climb with nothing to show for them."""
    boundary_buffer_m: float = 2000.0
    """How far outside the park boundary tiles are still rendered: enough for the approach
    roads, the gateway town and a trailhead just outside the line, without paying for the
    whole bounding box."""
    elevation_resolution_m: float = 10.0
    """Ground resolution the elevation grid is fetched at, matching 3DEP's 1/3 arc-second
    national coverage."""


DEFAULT_PACK_SETTINGS = PackSettings()

# The App Store's limit on a shipped app, and the thing the pilot is measuring against
# (SPECIFICATION.md §8, §16).
APP_STORE_LIMIT_BYTES = 4 * 1000 * 1000 * 1000

# Every national park gets a pack; the state-park list is still to be curated
# (SPECIFICATION.md §17, follow-up 1), so the size report costs state packs per park
# rather than pretending to know which ones.
NATIONAL_PARK_COUNT = 63


@dataclass(frozen=True)
class Settings:
    """Runtime configuration, read from the environment.

    Keys are never committed. ``Pipeline/.env.example`` lists what is needed, and
    ``.env`` is gitignored (``AGENTS.md`` §5).
    """

    nps_api_key: str | None = None
    ridb_api_key: str | None = None

    @classmethod
    def from_environment(cls) -> Settings:
        return cls(
            nps_api_key=os.environ.get("NPS_API_KEY") or None,
            ridb_api_key=os.environ.get("RIDB_API_KEY") or None,
        )

    def require_nps_key(self) -> str:
        if not self.nps_api_key:
            raise SystemExit(
                "NPS_API_KEY is not set. Copy Pipeline/.env.example to Pipeline/.env and "
                "add a key from https://www.nps.gov/subjects/developer/get-started.htm"
            )
        return self.nps_api_key


def ensure_directories() -> None:
    for directory in (RAW_DIR, WORK_DIR, OUT_DIR):
        directory.mkdir(parents=True, exist_ok=True)


def park(unit_code: str) -> Park:
    """Look up a park by NPS code, with a message that lists what there is."""
    try:
        return PARKS[unit_code.upper()]
    except KeyError:
        known = ", ".join(sorted(PARKS))
        raise SystemExit(f"unknown park {unit_code!r}. Known park codes: {known}") from None
