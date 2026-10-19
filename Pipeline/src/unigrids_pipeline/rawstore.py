"""The date-versioned raw store under ``raw/``.

``fetch``'s contract (``steps.fetch``) is that every download is versioned by date, "so a
dataset can be rebuilt exactly, and so a change in a source can be told apart from a
change in the pipeline". That is this module: each fetch writes into
``raw/<YYYY-MM-DD>/<source>/`` and drops a ``source.json`` beside the files recording
where they came from, what was asked for, how big they are, their SHA-256, and the terms
they arrived under.

The licence note is not decoration. OpenStreetMap is ODbL and Zion's pack owes it
attribution, so the terms have to travel with the bytes rather than live in somebody's
memory of which directory held what (``AGENTS.md`` §5).
"""

from __future__ import annotations

import datetime as dt
import hashlib
import json
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

from . import config


@dataclass(frozen=True)
class SourceTerms:
    """What a source is and what using it obliges the pack to say."""

    identifier: str
    title: str
    url: str
    licence: str
    attribution: str
    notes: str = ""


@dataclass
class FetchRecord:
    """The ``source.json`` written next to a fetched dataset."""

    source: SourceTerms
    fetched_at: str
    requests: list[dict[str, Any]] = field(default_factory=list)
    files: list[dict[str, Any]] = field(default_factory=list)

    def add_file(self, path: Path, *, root: Path, note: str = "") -> None:
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        self.files.append(
            {
                "path": path.relative_to(root).as_posix(),
                "bytes": path.stat().st_size,
                "sha256": digest,
                **({"note": note} if note else {}),
            }
        )

    def add_request(self, url: str, parameters: dict[str, Any] | None = None, **extra: Any) -> None:
        self.requests.append({"url": url, "parameters": parameters or {}, **extra})

    def write(self, directory: Path) -> Path:
        path = directory / "source.json"
        path.write_text(json.dumps(asdict(self), indent=2, sort_keys=False) + "\n")
        return path


def today() -> str:
    return dt.datetime.now(dt.UTC).strftime("%Y-%m-%d")


def utc_now() -> str:
    return dt.datetime.now(dt.UTC).replace(microsecond=0).isoformat()


def version_directory(source: str, version: str | None = None) -> Path:
    """``raw/<date>/<source>/``, created."""
    directory = config.RAW_DIR / (version or today()) / source
    directory.mkdir(parents=True, exist_ok=True)
    return directory


def versions(source: str) -> list[str]:
    """Every date a source has been fetched on, newest first."""
    if not config.RAW_DIR.exists():
        return []
    found = [
        child.name
        for child in config.RAW_DIR.iterdir()
        if child.is_dir() and (child / source).is_dir()
    ]
    return sorted(found, reverse=True)


def latest(source: str, *required: str) -> Path | None:
    """Newest version directory of ``source`` that holds all of ``required``.

    A half-finished fetch is skipped rather than half-read: the newest date wins only if
    it actually has the files the next step needs.
    """
    for version in versions(source):
        directory = config.RAW_DIR / version / source
        if all((directory / name).exists() for name in required):
            return directory
    return None


def require(source: str, *required: str) -> Path:
    directory = latest(source, *required)
    if directory is None:
        wanted = ", ".join(required) or "anything"
        raise FileNotFoundError(
            f"no fetched {source} found with {wanted} under {config.RAW_DIR}. "
            f"Run `unigrids-pipeline fetch --source {source}` first."
        )
    return directory


def read_terms(directory: Path) -> SourceTerms | None:
    """The terms recorded alongside a fetched dataset, for the pack's attribution."""
    path = directory / "source.json"
    if not path.exists():
        return None
    payload = json.loads(path.read_text())
    source = payload.get("source") or {}
    if not source.get("identifier"):
        return None
    return SourceTerms(
        identifier=source["identifier"],
        title=source.get("title", ""),
        url=source.get("url", ""),
        licence=source.get("licence", ""),
        attribution=source.get("attribution", ""),
        notes=source.get("notes", ""),
    )


def version_of(directory: Path) -> str:
    """The date a raw directory was fetched on, read back off its own path."""
    return directory.parent.name
