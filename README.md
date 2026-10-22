# Unigrids

A free, native Apple app (iPhone, iPad, Mac) for planning, exploring and logging visits
to US public lands — all on one map.

National parks get the deepest treatment: an interactive guide laid out in the style of
the NPS Unigrid brochures, the official brochure itself, a 3D view and a trail catalogue.
Other NPS units, state parks and major federal sites appear as rich map pins. Visits land
in a trip log and a digital passport stamp book, and the log turns into stats.

> **Not affiliated with the National Park Service.** Unigrids is an independent hobby
> project. It uses public-domain NPS material and public government data. It never uses
> the NPS arrowhead or implies endorsement.

## Status

**`0.9.0` — the production pass.** Every national park has a guide; 5,515 places — every
NPS unit, national forest and grassland, wildlife refuge, BLM monument and conservation
area, National Natural Landmark, national scenic byway and every PAD-US state park — are
on one map, each marked by type, with Interstate, US highway and Amtrak layers. Every
place opens in 3D, and Zion, Acadia, Yellowstone and Great Smoky Mountains have an offline
Park map in the app; 61 national parks have a measured trail catalogue. Trips take parks,
sights, trails, lodging and points on the way, with drive times, forecasts, live closures
and reminders, and alert notifications for parks on upcoming trips. Visits are logged by
hand, by arrival or from Photos, fill the passport and stats, export in full and import
back, and every change can be undone. Not built yet: widgets, the Watch app, and offline
packs for the other 59 parks. What has and has not been checked is in
[`docs/mvp-scope.md`](docs/mvp-scope.md).

The build follows the three phases in [`SPECIFICATION.md`](SPECIFICATION.md) §16:

| Phase | Milestone | Scope |
|---|---|---|
| Pilot | `0.1.0` | Four parks (Zion, Acadia, Yellowstone, Great Smoky Mountains) prove the data pipeline and the Unigrid guide template across three devices |
| MVP | `0.2.0` | A guide for every national park, plus manual and photo-import logging |
| Production pass | `0.9.0` | Everything for v1.0 but widgets and the Watch app; offline maps for the four pilot parks; refreshed data |
| v1.0 | `1.0.0` | Trails, offline maps, the planner, widgets, the Watch app, full logging and stats |

What runs today, and what is still stubbed, is tracked in
[`docs/mvp-scope.md`](docs/mvp-scope.md) and [`CHANGELOG.md`](CHANGELOG.md).

## Principles

- **Homage, not imitation.** Guides borrow the clarity of the 1977 Vignelli Unigrid
  system. Content is factual and built from public-domain NPS material.
- **Privacy-first.** Data stays on device and in the user's own iCloud. No accounts,
  no analytics, no social feed. Sharing is by exported cards.
- **Depth before breadth.** National parks are excellent before other tiers gain depth.
- **Works without signal where it matters.** Park maps and trails ship inside the app.
- **Nothing to run.** No servers or hosting — only Apple services and public APIs.

## Repository layout

```
.
├── SPECIFICATION.md         The living requirements document (source of truth)
├── AGENTS.md                Working agreement: conventions, commands, guardrails
├── CLAUDE.md                Pointer to AGENTS.md for Claude Code
├── CHANGELOG.md             Updated with every release
├── docs/                    Scope notes and architecture decision records
├── App/                     Thin Xcode app target (entry point, assets, entitlements)
│   ├── Unigrids.xcodeproj
│   └── Unigrids/
├── Packages/UnigridsKit/    Almost all of the code, as a local Swift package
│   ├── Sources/UnigridsCore        Domain model, value types, rules
│   ├── Sources/UnigridsReference   Read-only bundled reference data
│   ├── Sources/UnigridsLog         SwiftData user store (trips, visits, stamps)
│   ├── Sources/UnigridsDesign      Unigrid design system + native tokens
│   ├── Sources/UnigridsFeatures    SwiftUI screens
│   └── Tests/
├── Pipeline/                Offline Python pipeline that builds the bundled data
└── scripts/                 bootstrap / build / test / lint
```

Why a package rather than a fat app target: the logic is testable and compiles in
seconds with `swift build`, and the Xcode project holds only what an app bundle needs.
See [`docs/adr/0003-spm-first-thin-app-target.md`](docs/adr/0003-spm-first-thin-app-target.md).

## Requirements

- macOS 27 or later
- Xcode 27 or later (Swift 6.4, iOS 27 / macOS 27 SDKs)
- Python 3.12+ and [uv](https://docs.astral.sh/uv/) — only to run the data pipeline
- Optional: `swiftformat` and `swiftlint` (`brew install swiftformat swiftlint`)

## Getting started

```bash
scripts/bootstrap.sh     # resolve packages, check the toolchain
scripts/test.sh          # run the UnigridsKit test suite
scripts/build.sh         # build the app for the iOS Simulator and for macOS
scripts/write-secrets.sh # optional: live park alerts, from NPS_API_KEY in .env
```

Or open `App/Unigrids.xcodeproj` in Xcode and run the `Unigrids` scheme.

The package alone builds and tests without Xcode's build system:

```bash
cd Packages/UnigridsKit && swift test
```

## Data

Reference data (places, outlines, points of interest, trails, roads and rail, document
links, climate, guide content) is **read-only and bundled in the app**. It is produced by the Python pipeline in `Pipeline/` and replaced
with each app release; user data never stores anything but stable Unigrids IDs that point
at it. User data (trips, visits, check-ins, stamps) lives in SwiftData, synced through the
user's private iCloud database.

The reference data committed under
`Packages/UnigridsKit/Sources/UnigridsReference/Resources/reference/` is built by
`unigrids_pipeline reference` from a dated snapshot of the sources below. Its provenance,
photo policy and limits are recorded in that directory's `README.md`.

Live park alerts are optional: put a free NPS API key in `.env` as `NPS_API_KEY=…` and
run `scripts/write-secrets.sh` before building. Without it the app runs normally and the
alerts panel does not appear.

### Sources and attribution

| Source | Used for | Terms |
|---|---|---|
| [NPS API](https://www.nps.gov/subjects/developer/) | Park list, descriptions, fees, hours, visitor centres, alerts | Free key, rate-limited |
| [NPS brochure maps](https://npgallery.nps.gov/) and each site's maps and brochures pages | Official maps and brochures viewer | Public domain; no NPS seal or implied endorsement |
| [NPS Public Trails](https://mapservices.nps.gov/arcgis/rest/services/NationalDatasets/NPS_Public_Trails/MapServer/0) | Trail catalogue | Public NPS dataset |
| NPS Land Resources Division | National park and NPS unit boundaries | Public domain |
| NPS National Natural Landmarks | Landmark locations | Public domain |
| US Forest Service, US Fish and Wildlife Service, BLM | National forest and grassland, wildlife refuge, BLM monument and conservation area boundaries | Public domain |
| FHWA America's Byways | Scenic byway and All-American Road routes | Public domain |
| National Transportation Atlas Database (US DOT) | Interstates, US highways, Amtrak routes and stations | Public domain |
| Census TIGERweb | State boundaries, to say which states a place lies in | Public domain |
| [PAD-US (USGS)](https://www.sciencebase.gov/catalog/item/6759abcfd34edfeb8710a004) | Boundaries for state parks | Free download |
| [Wikimedia Commons](https://commons.wikimedia.org/) | Photographs of state parks, monuments and refuges | Per photograph: public domain, CC0, CC BY or CC BY-SA, credited in the app |
| [RIDB / Recreation.gov](https://catalog.data.gov/dataset/recreation-information-database-ridb-58364) | Facilities, campgrounds, booking deep links | CC BY |
| USGS 3DEP | Trail profiles, hillshade | Public domain |
| [OpenStreetMap](https://www.openstreetmap.org/copyright) | Roads, water and labels for offline tiles | ODbL — attribution and share-alike |
| [Open-Meteo](https://open-meteo.com/) | Trip forecasts, weather for each visit, ten-year monthly climate | CC BY 4.0; free for non-commercial use |
| WeatherKit | Planned for forecasts once a development team is wired in (`SPECIFICATION.md` §17) | Apple attribution required |

The app ships an Attributions screen covering all of the above, plus map attribution
wherever tiles are drawn. Licensing and naming constraints are tracked in
[`SPECIFICATION.md`](SPECIFICATION.md) §15.

## Contributing

Read [`AGENTS.md`](AGENTS.md) first — it is the working agreement for both humans and
coding agents, and it carries the guardrails that matter (no backend, no analytics, no
NPS arrowhead, no committed secrets).

## Licence

Code: see [`LICENSE`](LICENSE). Bundled NPS-derived content and third-party open data
keep their own terms, listed above and in the app's Attributions screen.
