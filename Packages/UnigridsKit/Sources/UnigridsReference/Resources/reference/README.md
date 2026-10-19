# Reference data

**Built by the pipeline, not edited here.** Everything in this directory is written by
`unigrids_pipeline reference` from the raw snapshot under `Pipeline/raw/<date>/` and the
curated files under `Pipeline/content/`. `manifest.json` records `"provenance":
"pipeline"` and the build date, and the app shows both in Settings. To change a fact, change
the content file or the raw source and rebuild; hand edits here are overwritten.

```bash
cd Pipeline
PYTHONPATH=src uv run python -m unigrids_pipeline reference --skip-fetch   # rebuild
PYTHONPATH=src uv run python -m unigrids_pipeline reference --refresh      # re-fetch first
```

Re-fetching needs `NPS_API_KEY` in `.env` (`AGENTS.md` §5).

`Pipeline/seed/build_seed.py` wrote the hand-authored pilot seed that this replaced. It is
superseded: running it would overwrite these files with the old four-park seed.

## What is here

| File | Contents | From |
|---|---|---|
| `manifest.json` | Dataset version, build date, provenance, a one-line note | The build |
| `places.json` | 537 places: 63 national parks, 373 other NPS units, 76 state parks, 25 monuments, conservation areas and refuges | NPS Data API; `content/national-parks.json`, `state-parks.json`, `federal-sites.json` |
| `pois.json` | 1,434 sights, visitor centres and campgrounds | NPS Data API places, visitor centres and campgrounds; sight choices and notes from the guides |
| `themes.json` | Theme tags | `content/themes.json` |
| `boundaries.json` | 506 outlines as encoded polylines, simplified | NPS Land Resources Division unit boundaries; USGS PAD-US 4.1 |
| `guides/np-*.json` | One guide per national park | `content/guides/`, merged with NPS fees, hours, weather, directions and photographs |
| `images/` | 235 photographs, resized and recompressed | NPS (public domain) for national parks; Wikimedia Commons for other places |

## Provenance and known limits

- **National park figures** — date established, area and 2025 recreation visits — come
  from `content/national-park-facts.json`, sourced from the NPS acreage report and NPS
  visitor statistics. Elevations, best seasons and suggested time come from the guides and
  are absent where no source gave them. An absent figure is correct; it is never filled
  by guess.
- **Guide prose and place summaries are written for Unigrids** and checked against the NPS
  Data API and Wikipedia. Other NPS units carry the NPS's own description, credited as
  such. Two new units with no NPS description yet show none.
- **Photographs.** A national park's photographs are NPS images whose credit names the
  NPS, which makes them US government works in the public domain; anything credited to a
  third party or marked as courtesy is excluded. Photographs of other places are from
  Wikimedia Commons and only under a reusable licence (public domain, CC0, CC BY or
  CC BY-SA), each with its credit, licence and source link. Every photograph is listed in
  Settings → Photo credits.
- **Outlines are for finding a place, not for navigation.** They are simplified
  (Douglas–Peucker at about 60 m for national parks, 120 m otherwise) and specks are
  dropped. PAD-US lags proclamations: Grand Staircase–Escalante still shows its
  pre-July-2026 boundary.
- **Coordinates** for sights are the NPS's own; where the NPS has none, the guide gives one
  and says so in its content file.
- **No trails.** `trails.json` is not built for the app yet; the store treats that as the
  expected state (§8).
- **Passport regions** for places without a curated region fall back to
  `PassportRegion.byState`, Unigrids' own grouping rather than the paper passport's
  (§17, follow-up 3).
