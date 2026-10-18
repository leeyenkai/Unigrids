# Pipeline

The offline pipeline that builds everything the app ships with. It runs locally (or on a
schedule) and writes into the app's resources; **it is not a server** and the app never
calls it (`docs/adr/0002`).

## Status

**Skeleton.** The six steps below exist as a CLI with their contracts written down, and
each raises a clear `NotImplementedError` describing what it must do. Nothing is
implemented yet. The reference data the app currently bundles is the hand-authored seed
in `seed/`, which is a stopgap — see
`../Packages/UnigridsKit/Sources/UnigridsReference/Resources/reference/README.md`.

## The six steps

From `SPECIFICATION.md` §12:

| Step | Does |
|---|---|
| `fetch` | Pulls each source into a raw store, versioned by date |
| `match` | Gives every place, sight and trail a stable Unigrids ID, mapped to NPS park codes and PAD-US unit IDs, so user logs survive data updates |
| `derive` | Trail length, elevation and profile; theme tags; passport region per site; climate normals; sight rankings |
| `edit` | Validates the curated files kept under version control (guide text, permits, seasonal notes) |
| `build` | Writes the bundled dataset and one offline pack per national park |
| `package` | Copies the dataset and packs into the app's resources, and re-checks every brochure link |

## Running it

```bash
cd Pipeline
uv sync
uv run unigrids-pipeline --help
uv run unigrids-pipeline fetch --source nps
uv run unigrids-pipeline all
```

An NPS API key is needed for `fetch`. Copy `.env.example` to `.env` and put the key
there; `.env` is gitignored, and no key ever goes in a commit (`AGENTS.md` §5).

## Why Python and not Swift

The pipeline joins half a dozen government datasets, several of them geospatial, and
renders map tiles. That is what the Python geo stack is for. It produces plain JSON (and
later SQLite and tiles) so nothing about the choice reaches the app.

## Directories

`raw/`, `work/` and `out/` are created at runtime and gitignored: downloads and
intermediates are large and reproducible, so the generator is the source of truth rather
than the artefacts.

`content/` holds the curated files that are **not** generated — guide text, permit rules,
seasonal notes. Those are prose and they belong under version control as prose.
