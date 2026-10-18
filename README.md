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

**Pre-release — milestone `0.1.0` (Pilot) in progress.**

The build follows the three phases in [`SPECIFICATION.md`](SPECIFICATION.md) §16:

| Phase | Milestone | Scope |
|---|---|---|
| Pilot | `0.1.0` | Four parks (Zion, Acadia, Yellowstone, Great Smoky Mountains) prove the data pipeline and the Unigrid guide template across three devices |
| MVP | `0.2.0` | A guide for every national park, plus manual and photo-import logging |
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
```

Or open `App/Unigrids.xcodeproj` in Xcode and run the `Unigrids` scheme.

The package alone builds and tests without Xcode's build system:

```bash
cd Packages/UnigridsKit && swift test
```

## Data

Reference data (places, points of interest, trails, guide content) is **read-only and
bundled in the app**. It is produced by the Python pipeline in `Pipeline/` and replaced
with each app release; user data never stores anything but stable Unigrids IDs that point
at it. User data (trips, visits, check-ins, stamps) lives in SwiftData, synced through the
user's private iCloud database.

The reference data currently committed under
`Packages/UnigridsKit/Sources/UnigridsReference/Resources/reference/` is a **hand-authored
pilot seed**, not pipeline output. It exists so the app has something real to render while
the pipeline is built. Its provenance and known gaps are recorded in that directory's
`README.md`.

### Sources and attribution

| Source | Used for | Terms |
|---|---|---|
| [NPS API](https://www.nps.gov/subjects/developer/) | Park list, descriptions, fees, hours, visitor centres, alerts | Free key, rate-limited |
| [NPS brochure maps](https://npgallery.nps.gov/) | Guide map panel, brochure viewer | Public domain; no NPS seal or implied endorsement |
| [NPS Public Trails](https://mapservices.nps.gov/arcgis/rest/services/NationalDatasets/NPS_Public_Trails/MapServer/0) | Trail lines | Public NPS dataset |
| [PAD-US (USGS)](https://www.sciencebase.gov/catalog/item/6759abcfd34edfeb8710a004) | Boundaries for state parks and federal sites | Free download |
| [RIDB / Recreation.gov](https://catalog.data.gov/dataset/recreation-information-database-ridb-58364) | Facilities, campgrounds, booking deep links | CC BY |
| USGS 3DEP | Trail profiles, hillshade | Public domain |
| [OpenStreetMap](https://www.openstreetmap.org/copyright) | Roads, water and labels for offline tiles | ODbL — attribution and share-alike |
| WeatherKit | Forecasts, sunrise/sunset, recent weather | Apple attribution required |
| [Open-Meteo](https://open-meteo.com/) | Weather for older visits, climate normals | CC BY 4.0; free for non-commercial use |

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
