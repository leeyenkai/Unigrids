"""The six pipeline steps (SPECIFICATION.md §12).

Each step's contract is written down here and each raises ``NotImplementedError`` with
what it must do. That is deliberate: a labelled stub is honest, and a step that silently
wrote nothing would be worse than one that says it is not built
(``AGENTS.md`` §10).
"""

from __future__ import annotations

from . import config


class StepNotBuiltError(NotImplementedError):
    """Raised by a step that is specified but not implemented yet."""


def fetch(source: str | None = None) -> None:
    """Pull each source into ``raw/``, versioned by date.

    Sources and their terms are in ``SPECIFICATION.md`` §12. Two things matter in the
    implementation:

    * **Version every download by date** so a dataset can be rebuilt exactly, and so a
      change in a source can be told apart from a change in the pipeline.
    * **Respect the rate limits.** The NPS key is per-key rate-limited and the same key
      ships inside the app, so the pipeline must not be the thing that exhausts it.
    """
    raise StepNotBuiltError(
        f"fetch({source or 'all'}) is not built. It must download the NPS API, NPS "
        "Public Trails, PAD-US, RIDB, USGS 3DEP and OpenStreetMap extracts into "
        f"{config.RAW_DIR}, each under a date-stamped directory."
    )


def match() -> None:
    """Give every place, sight and trail a stable Unigrids ID.

    The mapping from source keys (NPS park code, PAD-US unit id) to Unigrids IDs is
    **persisted**, not recomputed: user logs point at these IDs, so an ID that changes
    silently orphans someone's visit. See ``ids.py``.
    """
    raise StepNotBuiltError(
        "match() is not built. It must assign stable Unigrids IDs, persist the mapping "
        "from NPS park codes and PAD-US unit IDs, and fail loudly when a previously "
        "issued ID would change."
    )


def derive() -> None:
    """Compute everything the sources do not publish directly.

    Trail length, elevation gain and loss, and the elevation profile, all measured the
    same way from the route line and USGS elevation so no trail's numbers depend on who
    published them. Plus theme tags, the passport region for every site, monthly climate
    normals, and sight rankings.
    """
    raise StepNotBuiltError(
        "derive() is not built. It must compute trail measurements from route lines and "
        "3DEP elevation, theme tags, passport regions, climate normals and sight ranks."
    )


def edit() -> None:
    """Validate the curated, hand-written content in ``content/``.

    Guide text, permit and timed-entry rules, and seasonal notes are prose kept under
    version control. This step checks they parse, that every ID they reference resolves,
    and that every guide cites a source.
    """
    raise StepNotBuiltError(
        f"edit() is not built. It must validate the curated files in {config.CONTENT_DIR} "
        "against the matched dataset and reject dangling IDs or uncited guides."
    )


def build() -> None:
    """Write the bundled dataset and one offline pack per national park.

    The dataset becomes read-only SQLite (§3, §13); the packs are topo tiles rendered
    from 3DEP and OpenStreetMap, plus trails, sights and guide content for the park
    extent.

    **The pack size is the pilot's whole question.** Build Zion first, measure it, and
    report whether 63 parks plus the curated state parks fit inside the App Store's 4 GB
    limit (§16, ``docs/mvp-scope.md``).
    """
    raise StepNotBuiltError(
        f"build() is not built. It must write the SQLite dataset and offline packs into "
        f"{config.OUT_DIR} and report each pack's size."
    )


def package() -> None:
    """Copy the dataset and packs into the app's resources, and re-check brochure links.

    NPS brochure URLs are not standardised across parks and they move, so every stored
    link is re-checked here and a broken one is recorded so the viewer can fall back to
    the park's NPS maps page (§6, §12).
    """
    raise StepNotBuiltError(
        f"package() is not built. It must copy the built dataset into "
        f"{config.APP_RESOURCES} and re-verify every brochure link."
    )


ALL_STEPS = (fetch, match, derive, edit, build, package)
