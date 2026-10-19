# Milestone 0.2.0 — MVP, for a first demo

The owner's brief for this round: take the app to a state that can be tested and shown to
friends — overviews for every national park, a detailed map with every major place
outlined and a tap-for-overview on each, and the functionality filled out — in a design
language of its own. This section records what that produced. The pilot record (0.1.0)
follows it unchanged.

## Built in 0.2.0

| Area | What works | Specification |
|---|---|---|
| Reference data | Built by the pipeline from the NPS Data API, NPS boundaries, PAD-US, Wikipedia and Wikimedia Commons: 537 places, 1,434 sights, visitor centres and campgrounds, 506 outlines, 235 photographs | §12 |
| Map | Every place as a tier-shaped marker, outlines (all national parks at every zoom, the rest from regional zoom), clustering, tap-inside-outline selection, region shortcuts, tier and visited filters, search across places and sights, three base maps | §5, ADR 0008 |
| Overview panel | Photograph and credit, written summary, figures, visit status, check in, stamp, add to trip, guide, directions | §5 |
| Guides | All 63 national parks: written summary, story, sights on the park map, visitor centres, plan your visit with fees and hours, weather, getting there, chronology, safety, regulations, gallery, sources; live alerts with a key; Explore in 3D | §6, §7 |
| Other places | A leaflet page for each of the 474 other places; written overviews for the 101 curated state parks and federal sites | §5 |
| Trips | Ordered stops with dates, route map, straight-line distance, `.ics` export, add to trip from anywhere, planned places dashed on the map; check-ins attach to a trip | §9, §10 |
| Passport, Stats | Region pages with completion, America 250 page; park grid, state tile map, figures, themes, nearest unvisited, share card | §9, §11 |
| Ownership | Export everything as JSON and visits as CSV | §9 |
| Identity | One design language on every screen | §14, ADR 0007 |
| Onboarding | Three panels and the non-affiliation notice | §14 |

## Not built in 0.2.0

Trail catalogue and offline packs in the app, the official brochure viewer,
auto-detected visits, photo import, drive times and planner conflict flags, alert badges
on the map, weather snapshots per visit, widgets and the Watch app. The tier-4 data
(national forests, grasslands, natural landmarks, byways) is not in yet.

## Checked, and not checked

- [x] `scripts/test.sh` and `scripts/build.sh` pass: 134 tests; the app builds for the iOS
      Simulator and macOS without warnings.
- [x] Every national park has a guide that decodes, with a written summary, at least three
      sights and a visitor centre; every curated state park and federal site has a
      written summary (`BundledDataTests`).
- [x] On macOS: onboarding, the map with outlines and clusters, a tap inside an outline,
      search, the overview panel, a guide end to end, a leaflet page, a trip from empty
      to two stops and back, Passport and Stats.
- [ ] **iPhone and iPad.** Still not seen running: the machine has no iOS 27 Simulator
      runtime (see 0.1.0 below). This is the first thing to check before a TestFlight
      build goes to anyone.
- [ ] **iCloud sync**, for the same reason as in 0.1.0: no development team is wired in.
- [ ] **Live alerts** need `scripts/write-secrets.sh` run once on the building machine.

# Milestone 0.1.0 — Pilot scope

[`SPECIFICATION.md`](../SPECIFICATION.md) §16 puts a four-park pilot before the MVP,
because the pilot answers the two questions that shape everything after it:

1. Does one Unigrid guide template reflow well across iPhone, iPad and Mac?
2. How large is an offline pack really — and does the whole bundle fit in 4 GB?

This milestone answers the first and builds the frame that lets the second be measured.
The pilot parks are **Zion, Acadia, Yellowstone and Great Smoky Mountains**.

## Assumption on record

The owner asked for "the first MVP". Read against §16, that is this pilot rather than the
`0.2.0` MVP: a guide for all 63 parks needs pipeline output that does not exist yet, while
the template, the data model, the log and the passport can all be proven on four parks
with a hand-authored seed. If the intent was the broader `0.2.0` scope, the gap is data
volume, not architecture — the pipeline fills it without reshaping the app.

## Built in 0.1.0

| Area | What works | Specification |
|---|---|---|
| Map home | All 63 national parks as pins, tier and visited styling, region shortcuts, search, bottom card with actions | §5 |
| Parks directory | Searchable, sortable list with visit status | §4, §5 |
| Unigrid guide | Title band, at a glance, the story, map placeholder, major sights, visitor centres, plan your visit, chronology, credits — in a responsive panel grid | §6 |
| Trip log | Manual check-in with date, notes, rating; visit list; edit and delete | §9 |
| Passport | Nine regions in their own ink, slot pages, stamp sheet, deterministic impressions, America 250 overprint for 2026 dates, verified tick when stamped on site | §9 |
| Stats | Parks and states visited, completion ring, visits by year, nearest unvisited park | §11 |
| Data model | Reference and user stores separated, stable IDs, CloudKit-ready SwiftData | §13 |
| Design system | Unigrid tokens and panel grid; native tokens for everything else | §14 |

## Deliberately not built yet

Each of these is specified and deferred, not forgotten. The UI says so where a user
would otherwise expect it to work.

| Area | Lands in | Why deferred |
|---|---|---|
| Trail catalogue | 1.0.0 | The pipeline now measures trails (Zion: 44 trails, 116 km, with profiles), but no screen reads them and difficulty, route type and sights along the way are not derived (§8) |
| Offline map packs | 1.0.0 | Zion's pack is built and measured, but the app has no tile-overlay screen, so `package` deliberately does not copy packs into its resources (§8) |
| 3D park exploration | 1.0.0 | MapKit camera work on top of a proven guide; online-only, so not on the pilot's critical path (§7) |
| Official brochure viewer | 0.2.0 | Needs a checked brochure link per site from the pipeline's package step (§6) |
| Planner, alerts, permits, weather | 1.0.0 | Needs live NPS API and WeatherKit integration, which needs a key and an entitlement (§10) |
| Auto-detected visits | 1.0.0 | Core Location region monitoring with a rotating watch set (§9) |
| Photo-library import | 0.2.0 | PhotoKit geotag scan (§9) |
| Tiers 2–4 (other NPS units, state parks, federal sites) | 0.2.0+ | Needs PAD-US and the full NPS unit list from the pipeline (§5) |
| Widgets, watchOS app | 1.0.0 | §3 |
| Export (JSON, CSV, GPX), share cards | 1.0.0 | §9, §11 |

## Exit criteria

- [x] `scripts/test.sh` and `scripts/build.sh` both pass — 72 tests, and the app builds
      for the iOS Simulator and for macOS with no warnings.
- [x] A visit can be logged, stamped and deleted, and the passport and the log agree
      afterwards. Checked in the running macOS app: stamping Acadia produced an
      impression on the North Atlantic page *and* a visit in Trips *and* a figure in
      Stats, from one action.
- [x] A 2026-dated stamp carries the America 250 seal and a 2025-dated one does not.
      Covered by tests at the rule and the store, and seen on screen.
- [x] The guide renders a pilot park on Mac, three columns at a 1180-point window, with
      the title band, at-a-glance, story, sights, visitor centres and plan panels.
- [ ] **The guide on iPhone and iPad.** Not verified: no iOS 27 simulator runtime is
      installed on this machine (the SDK is 27.0, the available runtimes are 26.5), so
      the app cannot be run on a simulator. The column maths is unit-tested at every
      device width, but the rendering is not. Install an iOS 27 runtime, or lower
      `IPHONEOS_DEPLOYMENT_TARGET` and the package's iOS platform to 26.0 — a two-line
      change — if targeting one generation back is acceptable.
- [ ] **Dynamic Type at accessibility sizes**, on a device. Unit-tested
      (`UnigridGridTests`), not seen.
- [ ] **iCloud sync.** The entitlements file exists but is deliberately not wired into
      the build (see `App/Unigrids/Unigrids.entitlements`), because an iCloud entitlement
      needs a development team and would break the build for anyone cloning the
      repository. The app stores locally until it is wired.
- [x] **One offline pack rendered for Zion and measured.** Zion's pack is **22.2 MB** —
      5,063 tiles at zoom 10–16, 256 px WebP, clipped to the park boundary plus a 2 km
      buffer, covering 602 km², plus 0.27 MB of measured trails. Built by
      `uv run unigrids-pipeline build` from `Pipeline/`; the full breakdown is
      `Pipeline/out/pack-size-report.md`, regenerated on every build.

## Does the bundle fit in 4 GB?

Yes, but not at full depth everywhere, and the format matters more than anything else.

The tile *counts* below are computed from each of the 63 parks' own NPS boundaries,
buffered and counted exactly as Zion's were. Only the *bytes per tile* are carried over
from Zion, which is dense canyon terrain and so errs high.

| All 63 national parks | WebP q82 | 256-colour PNG | PNG |
|---|---:|---:|---:|
| zoom 10–16 everywhere | 12.4 GB | 114.8 GB | 148.6 GB |
| zoom 10–15 everywhere | 5.4 GB | 37.6 GB | 55.9 GB |
| zoom 10–14 everywhere | 2.3 GB | 11.1 GB | 19.5 GB |
| by area: z16 ≤2,000 km², z15 ≤10,000, z14 above | 3.3 GB | 21.0 GB | 32.3 GB |
| by area, wilderness shallower: …z13 above | **2.2 GB** | 14.6 GB | 21.8 GB |

Three things to trim, in the order they are worth trimming:

1. **Tile format — worth 8×, and costs nothing visible.** A park tile is shaded relief:
   continuous tone, which is what PNG compresses worst. On the same tiles, Zion averages
   50 KB per tile as PNG, 35 KB quantised to 256 colours, and 6 KB as WebP at quality 82.
   The difference does not survive a side-by-side (PSNR 37 dB — trail dashes and road
   casings stay crisp). **Ship WebP.** iOS has decoded it natively since 14.
2. **Deep zooms, but by park, not across the board.** Six Alaskan park-and-preserve units
   hold 77 % of the national tile count; Wrangell–St. Elias alone encloses a hundred times
   Zion's area, almost all roadless wilderness with no trail network to draw at 2 m per
   pixel. Capping those at zoom 13 while small parks keep zoom 16 costs 2.2 GB, against
   5.4 GB for taking one zoom level off every park alike. Zoom 16 is also interpolated
   relief wherever 3DEP has only its 10 m national coverage.
3. **State parks are not the problem.** A 25 km² state park costs about 2 MB at full
   depth, so a curated hundred is another 200 MB. `SPECIFICATION.md` §17 follow-up 1 can
   be decided on merit rather than on budget.

Clipping tiles to the park boundary rather than its bounding box is already in the 22.2 MB
figure, and is worth 47 % of the tiles at zoom 16 for a park shaped like Zion.

**The one unmeasured item that could still break this** is the brochure PDFs. §8 puts one
in each pack and nothing has measured them. At 12 MB a park they are 0.8 GB, which turns
the 3.3 GB middle policy into 4.06 GB — over. They should be measured in the `package`
step before the budget is treated as closed. The app binary, the reference database and
the app's assets are also outside these totals.

The decision is recorded in
[`docs/adr/0006-offline-pack-format.md`](adr/0006-offline-pack-format.md).

## Still open after this milestone

Three of the exit criteria above are unmet, and none of them is blocked on a decision:

- the guide on iPhone and iPad, and Dynamic Type at accessibility sizes, both need an
  iOS 27 simulator runtime on the machine;
- iCloud sync needs a development team before the entitlement can be wired in.

And three things this milestone's pack work leaves for the next one:

- **Measure the brochure PDFs.** The only part of the 4 GB budget still unmeasured, and
  big enough to change the answer.
- **Pick the zoom tier rule on something better than area.** Death Valley is 13,900 km²,
  road-accessible and busy, and lands in the same tier as Gates of the Arctic. Trail
  density or visitation would be the better rule, and needs the trails fetched nationally.
- **Give the app something that reads a pack**, since until then nothing exercises the
  MBTiles row flip or the tile overlay in anger.
