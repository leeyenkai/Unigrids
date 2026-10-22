# Pipeline

The offline pipeline that builds everything the app ships with. It runs locally (or on a
schedule) and writes into the app's resources; **it is not a server** and the app never
calls it (`docs/adr/0002`).

## Status

**Three steps of six, for one park.** `fetch`, `derive` and `build` do what an offline
pack needs: the keyless sources, the trail measurements, and a rendered pack with its size
measured. `match`, `edit` and `package` are still labelled stubs that raise
`StepNotBuiltError` with their contracts, and so are the parts of `fetch` that need an API
key nobody has supplied.

That slice was chosen because the pack size was the pilot's open question
(`SPECIFICATION.md` §16, `docs/mvp-scope.md`). It is answered: see
`out/pack-size-report.md` after a build, and the summary in `docs/mvp-scope.md`.

Separately, the **`reference`** command builds the reference data the app bundles — every
place, outline, sight, trail, road and rail line, document link, climate table, guide and
photograph — from the NPS Data API, NPS boundaries, the federal land agencies' own
boundary services, the National Transportation Atlas, NPS Public Trails with USGS 3DEP,
each NPS site's own pages, Open-Meteo, PAD-US and Wikimedia Commons. It replaced the hand-authored seed in `seed/`, which is kept for
history and must not be run (it would overwrite the built data). See
`../Packages/UnigridsKit/Sources/UnigridsReference/Resources/reference/README.md`.

## Reference data

```bash
cd Pipeline
PYTHONPATH=src uv run python -m unigrids_pipeline reference              # fetch today's snapshot if missing, then build
PYTHONPATH=src uv run python -m unigrids_pipeline reference --skip-fetch # rebuild from the latest snapshot
PYTHONPATH=src uv run python -m unigrids_pipeline reference --refresh    # re-fetch everything
```

(`PYTHONPATH=src` because Python 3.13 skips the hidden `.pth` file an editable install
writes into an iCloud-synced folder.)

| Stage | Module | Does |
|---|---|---|
| Fetch | `reference_fetch.py` | NPS Data API parks, visitor centres, stamp locations, places, campgrounds and activities, one park at a time (`sources/npsapi.py`); NPS unit boundaries; PAD-US fee and management layers for curated state parks; Wikipedia summaries and Commons licence metadata; candidate photographs; then each of the modules below. Into `raw/<date>/` |
| Lands and transport | `lands_fetch.py`, `lands_build.py` | Forest Service proclaimed forests and grasslands, FWS refuge boundaries, BLM National Conservation Lands, NPS National Natural Landmarks, FHWA byways and Census states; NTAD Interstates, US routes and Amtrak routes and stations. Names cleaned (title case, refuge suffixes, BLM overrides by NLCS ID), states found by sampling each outline against state polygons |
| Trails | `trail_catalogue.py` | NPS Public Trails per national park, joined by name and kept inside the park's outline; 3DEP sampled every 30 m (cached per park); length, climb, profile, loops, features, sights along the way |
| Documents | `brochures.py` | Each NPS site's `maps.htm` and `brochures.htm`, every PDF link checked with a request before it is recorded |
| Climate | `climate.py` | Ten years (2016–2025) of Open-Meteo archive daily weather per national park, reduced to monthly mean high, low and precipitation |
| Build | `reference_build.py` | Joins those with `content/` and writes `places`, `pois`, `themes`, `boundaries`, `boundaries-overview`, `routes`, `transport`, `trails`, `brochures`, `climate`, `guides/`, `images/` and `manifest` into the app's resources |
| Geometry | `outline.py` | Polygon extraction, Douglas–Peucker simplification, speck removal, polyline encoding, label points |
| Content rules | `reference_content.py` | Which photographs are public domain, which places are curated, how guide content is read |

A national park's photographs must be NPS-credited public-domain images; other places'
photographs must carry a reusable Commons licence. The build prints any place left without
a summary or any guide sight it could not place.

The raw snapshot is about 1.1 GB, most of it photographs (0.85 GB), then the
transportation layers, trails and federal lands; `raw/` is gitignored. Every fetch is
resumable: a file already in today's snapshot is left alone, so an interrupted fetch picks
up where it stopped. Refused ArcGIS pages are retried twice before the fetch gives up.

## The six steps

From `SPECIFICATION.md` §12:

| Step | Does | State |
|---|---|---|
| `fetch` | Pulls each source into a raw store, versioned by date | Built for the keyless sources: NPS boundaries, NPS Public Trails, USGS 3DEP, OpenStreetMap |
| `match` | Gives every place, sight and trail a stable Unigrids ID, mapped to NPS park codes and PAD-US unit IDs, so user logs survive data updates | Stub |
| `derive` | Trail length, elevation and profile; theme tags; passport region per site; climate normals; sight rankings | Trail measurements built; the rest is a stub |
| `edit` | Validates the curated files kept under version control (guide text, permits, seasonal notes) | Stub |
| `build` | Writes the bundled dataset and one offline pack per national park | One park's pack and the size report built; the SQLite dataset is a stub |
| `package` | Copies the dataset and packs into the app's resources, and re-checks every brochure link | Stub |

## Running it

```bash
cd Pipeline
uv sync
uv run unigrids-pipeline --help

# One park's offline pack, end to end. No API key needed for any of this.
uv run unigrids-pipeline fetch --park ZION
uv run unigrids-pipeline derive --park ZION
uv run unigrids-pipeline build --park ZION
```

`build` writes the pack to `out/packs/<place-id>/` and a size report to
`out/pack-size-report.md`, and takes about ten minutes for Zion on a laptop — most of it
rendering five thousand tiles.

A source already fetched today is left alone on a second run; pass `--refresh` to download
it again. These are free public services, two of them government and one volunteer-funded,
and re-pulling sixty megabytes to get the same bytes is not a neighbourly thing to do.

An NPS API key is needed for the NPS Data API (used by `reference`) and RIDB (not built yet). Copy
`.env.example` to `.env` and put the key there; `.env` is gitignored, and no key ever goes
in a commit (`AGENTS.md` §5).

## What a pack contains

`out/packs/np-zion/`:

| File | What |
|---|---|
| `tiles.mbtiles` | Topo-style raster tiles, read-only SQLite. MBTiles stores TMS rows, so flip `y` for `MKTileOverlay`'s XYZ — the manifest says so too |
| `trails.json` | Every trail measured the same way, with its elevation profile and the method that produced it |
| `manifest.json` | Extent, zooms, per-zoom tile counts and bytes, source versions, and what the pack does **not** contain yet |
| `ATTRIBUTION.md` | What the pack owes each source, including why the ODbL's share-alike is not engaged by rendered tiles and when it would be |

Tiles are relief-shaded terrain from 3DEP with OpenStreetMap roads and water and NPS
trails over it — shaded relief rather than contour lines, which is what an NPS brochure
map uses. No NPS arrowhead and no seal (`AGENTS.md` §5).

## Adding a park

`config.PARKS` keyed by NPS park code. The four pilot parks are there; everything else
about a park is fetched from its unit code.

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
