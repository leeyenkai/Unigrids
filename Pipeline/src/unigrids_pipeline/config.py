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
