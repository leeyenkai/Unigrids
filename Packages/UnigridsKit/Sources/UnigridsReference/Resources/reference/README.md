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
| `manifest.json` | Dataset version (5 with places beyond the US; a US-only build writes 4), build date, provenance, a note per country | The build |
| `places.json` | 5,623 places. **United States**, 5,057: 63 national parks, 373 other NPS units, 3,081 state parks, 154 national forests, 20 national grasslands, 548 wildlife refuges, 33 national monuments, 24 BLM conservation areas, 575 National Natural Landmarks, 186 scenic byways. Each has a time zone; NPS sites carry monthly visitation (378) and visitor information (373); state parks name their manager where PAD-US gives one (2,358); 2,717 carry a Wikipedia lead. **Japan**, 93: 35 national parks and 58 quasi-national parks. **Norway**, 473: 48 national parks, 195 protected landscapes and 230 nature reserves of 10 km² or more. Every place abroad has its subdivisions, passport region and time zone; every national park and quasi-national park its local name | NPS Data API and Visitor Use Statistics; PAD-US 4.1; USFS, FWS, BLM and NPS NNL services; FHWA byways; Wikipedia; MOE; Miljødirektoratet; Wikidata; `content/` |
| `pois.json` | 2,475 points: 1,660 US sights, visitor centres, campgrounds and stamp locations; 380 in Japan and 435 in Norway, huts among them | NPS Data API; the guides' sights; OpenStreetMap huts (ODbL) |
| `themes.json` | Theme tags | `content/themes.json` |
| `boundaries.json` | 4,770 outlines as encoded polylines, simplified: 4,260 US, 37 Japanese (every national park and two quasi-national parks), 473 Norwegian | NPS Land Resources Division; USFS; FWS; BLM NLCS; PAD-US 4.1; MOE `nps.zip` (zones joined); OpenStreetMap; Miljødirektoratet |
| `boundaries-overview.json` | The same outlines simplified harder (about 0.008°), drawn at country scale | The build |
| `routes.json` | 186 byway routes as encoded polylines | FHWA America's Byways |
| `transport.json` | 241 Interstate and 254 US route lines, 49 Amtrak routes and 569 stations; 596 passenger rail lines and 1,280 stations in Japan and Norway | National Transportation Atlas Database (NHS, Amtrak); OpenStreetMap (ODbL) |
| `trails.json` | 4,608 trails: 3,506 in 61 US national parks (3,486 measured), 546 in 27 Japanese and 556 in 41 Norwegian parks (all measured; 240 with Turrutebasen's published grade). Each has its line, length, climb, high and low point, profile, loop, features, sights along the way, uses, seasonal notes | NPS Public Trails; OpenStreetMap for Sequoia and Kings Canyon and for Japan (ODbL); Kartverket's Turrutebasen (CC BY 4.0); USGS 3DEP elevation; Copernicus GLO-30 abroad |
| `brochures.json` | For 434 NPS sites: the maps page, and any PDFs its maps and brochures pages list (84 sites list at least one); Japan's 35 parks with MOE's brochures; Norway's 48 park pages | Each site's `nps.gov/<code>/planyourvisit/` pages; japan.travel and env.go.jp; norgesnasjonalparker.no |
| `climate.json` | Monthly mean high, low and precipitation for each of the 146 national parks, 2016–2025 | Open-Meteo archive (ERA5), CC BY 4.0 |
| `guides/*.json` | One guide per national park, 146 | `content/guides/`, merged with NPS fees, hours, weather, directions and photographs |
| `images/` | 548 national park photographs (US, Japan, Norway), resized and recompressed, each named for its source | NPS (public domain); other places link their Wikimedia Commons photographs |

## Provenance and known limits

- **Japan and Norway** (ADR 0013). Guides are written for Unigrids and every claim was
  checked against the parks' authorities (`docs/sources-japan-norway.md`). Japan's
  national park areas and dates follow MOE's table; their outlines join the zones of
  MOE's `nps.zip`, a 2025 file MOE no longer links. Quasi-national parks come from MOE's
  list with Wikidata's designation year; OpenStreetMap outlines 6 of the 58 by name, of
  which the 2 between half and twice the published area are kept, so 56 are points. Norway's
  areas are each regulation's own figure; a landscape's or reserve's year is when it was
  first protected (`foerstegangVernet`), absent where Miljødirektoratet gives only the
  current regulation's date. Photographs are from Wikimedia Commons, each with its own
  credit and licence. Lowest and highest ground abroad is measured on Copernicus GLO-30
  and says so; its 30 m cells run a few metres under the named summits. Huts for 32
  Japanese parks, Japan's main stations and Shinkansen lines, and trails for eight
  parks wait on OpenStreetMap's query service, which refused this build's machine
  part-way.

- **National park figures** — date established, area and 2025 recreation visits — come
  from `content/national-park-facts.json`, sourced from the NPS acreage report and NPS
  visitor statistics. Elevations, best seasons and suggested time come from the guides and
  are absent where no source gave them. An absent figure is correct; it is never filled
  by guess.
- **Guide prose and the curated places' summaries are written for Unigrids** and checked
  against the NPS Data API and Wikipedia. Other NPS units carry the NPS's own description,
  credited as such. Two new units with no NPS description yet show none.
- **Wikipedia leads** describe 2,717 US places with no agency prose — state parks,
  forests, refuges, landmarks, byways, BLM lands. A lead is used only when the article's
  title, or its own opening ("formerly", "officially", "also known as"), names the place,
  its coordinates fall inside the outline (within 10 km for a point or a route), and it is
  not about a town; 380 articles failed that and are listed in
  `Pipeline/work/wikipedia-report.json`. The lead is cut to its first sentences, so the
  app says "Adapted from" with the article, its link and CC BY-SA 4.0. Fifteen state parks
  PAD-US still lists whose own article says they have closed, or that the state has
  handed on (Hart, now the City of Hartwell's), are left out.
- **State parks** are PAD-US units a state body manages, or whose own name carries a
  state designation: PAD-US also files Buffalo's traffic triangles and town playgrounds
  as state parks, and those are left out. A sliver PAD-US files under a neighbouring
  state joins the park it belongs to. Places with no match carry one line built from their
  own fields (kind, states, agency) and nothing more.
- **Visitation** is the mean of the NPS's monthly recreation visits over 2022–2025, and
  2025's annual total, from the NPS Visitor Use Statistics (CC0).
- **Time zones** are each place's own IANA zone, found from its centre; a park across
  two zones takes the zone of its main visitor centre.
- **Names** are the agencies' own, cleaned only in form: title case for all-caps sources,
  the "National Wildlife Refuge" suffix restored where a source dropped it, and a short
  list of BLM overrides keyed by NLCS ID. FWS administrative sites are left out.
- **States** for agency lands are found by sampling each outline against Census state
  polygons, so a forest that only grazes a state line is not credited to it (a state
  needs about 5 % of the samples). Eleven remote Pacific and Caribbean refuges and marine
  monuments lie in no state and carry none.
- **Photographs.** A national park's photographs are NPS images whose credit names the
  NPS, which makes them US government works in the public domain; anything credited to a
  third party or marked as courtesy is excluded. Photographs of other places are from
  Wikimedia Commons and only under a reusable licence (public domain, CC0, CC BY or
  CC BY-SA), each with its credit, licence and source link. Agency lands have no
  photographs. Every photograph is listed in Settings → Photo credits.
- **Outlines and lines are for finding a place, not for navigation.** They are simplified
  (Douglas–Peucker at about 60 m for national parks, 120 m for agency lands and state
  parks, 100 m for byways and rail, 200–300 m for highways) and specks are dropped. PAD-US
  lags proclamations: Grand Staircase–Escalante still shows its pre-July-2026 boundary.
- **Trails** are measured by the pipeline, not copied: lengths are as mapped (one way, or
  once round a loop), climbs from 3DEP sampled every 30 m and smoothed over 90 m, each
  trail laid out in the direction people walk it — from the end nearer a trailhead, or
  the lower end. Twenty trails the elevation service could not cover keep their length
  and no climb. Difficulty is not stored: the app estimates it from distance and climb and
  says so. Sequoia and Kings Canyon publish no trails in the NPS layer, so theirs are
  OpenStreetMap's named paths, credited under the ODbL; Gates of the Arctic and Kobuk
  Valley are trailless wilderness and have none.
- **Elevation ranges** for 42 national parks the NPS gives no figure for are measured
  from 3DEP within the outline, and say so.
- **Document links** are only those an NPS site's own pages list, each checked to answer
  before it is recorded. NPS links move; a re-fetch before each release re-checks them.
- **Coordinates** for sights are the NPS's own; where the NPS has none, the guide gives one
  and says so in its content file.
- **Passport regions** for places without a curated region fall back to
  `PassportRegion.byState`, Unigrids' own grouping rather than the paper passport's
  (§17, follow-up 3).
