# Reference data — pilot seed

**This directory is a hand-authored stopgap, not pipeline output.** It exists so the app
has real places to render while `Pipeline/` is built. `manifest.json` says so too:
`"provenance": "seed"`, which the app surfaces on its data screen.

## What is here

| File | Contents | Authored by |
|---|---|---|
| `manifest.json` | Dataset version, build date, provenance | `Pipeline/seed/build_seed.py` |
| `places.json` | All 63 national parks | `Pipeline/seed/build_seed.py` |
| `pois.json` | Sights and visitor centres for the four pilot parks | `Pipeline/seed/build_seed.py` |
| `themes.json` | 18 theme tags across geology, ecosystem and history | `Pipeline/seed/build_seed.py` |
| `guides/np-*.json` | Guide content for the four pilot parks | Hand-edited, not generated |

Regenerate the generated files with:

```bash
python3 Pipeline/seed/build_seed.py
```

The guide files are deliberately left alone by that script — they are prose, and prose
belongs under version control as prose.

## Provenance and known gaps

Read this before treating anything here as a fact.

- **Coordinates are approximate.** Park centres are rounded to two decimal places and POI
  locations to four. Good enough to place a pin and frame a camera; not survey data.
- **Figures are unverified.** The at-a-glance numbers for the four pilot parks
  (established year, area, elevation range, annual visits, fee) were authored from general
  knowledge and have **not** been checked against the NPS API. Visitation is rounded to
  the nearest hundred thousand specifically so it does not read as a published figure.
  The other 59 parks carry no figures at all, which renders as absent rather than as a
  guess — that is the correct behaviour, not a gap to fill by hand.
- **No boundaries.** Only the four pilot parks carry an extent, and none carries a
  polygon. Boundary tinting (§5) needs PAD-US geometry from the pipeline.
- **No trails.** `trails.json` does not exist yet; the store treats that as the expected
  state. The catalogue needs the NPS Public Trails dataset (§8).
- **No images.** There are no hero photographs and no brochure maps, because only
  photographs confirmed public domain may be reused in native guides (§15) and that
  confirmation is part of the pipeline's work. The guide renders a labelled placeholder
  where the brochure map will go.
- **Passport regions are inferred.** No place here carries a curated `passportRegion`, so
  every one falls back to `PassportRegion.byState`. That fallback is Unigrids' own
  grouping, not the paper passport's assignments — see §17, follow-up 3.
- **Tiers 2–4 are absent.** Other NPS units, state parks and federal sites need the full
  NPS unit list and PAD-US (§5).

## When the pipeline lands

The pipeline's build step writes these same filenames, with `"provenance": "pipeline"`,
into `../generated/` — which is gitignored, because generated data belongs to the
generator. At that point delete this directory and `Pipeline/seed/`, and point
`BundledReferenceStore` at `generated`.
