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
| Trail catalogue | 1.0.0 | Needs the NPS Public Trails dataset and pipeline-computed length, gain and profiles (§8) |
| Offline map packs | 1.0.0 | Needs rendered topo tiles; pack size is the thing the pilot measures (§8) |
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
- [ ] **One offline pack rendered for Zion and measured**, giving a real number for the
      4 GB question.

The last item is the pilot's actual purpose and is the first thing to pick up after this
milestone's app work.
