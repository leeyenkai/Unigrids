# Changelog

All notable changes to Unigrids are recorded here.

The format follows [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/) and the
project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Until `1.0.0`,
minor versions are the milestones in [`SPECIFICATION.md`](SPECIFICATION.md) §16: `0.1.0`
is the four-park pilot, `0.2.0` the MVP, `1.0.0` the full release.

Every user-visible change adds a line under `## [Unreleased]` in the same commit that
makes the change. A release moves that block under a version heading with its date.

## [Unreleased]

### Added

- Repository scaffolding: `README.md`, `.gitignore`, `.editorconfig`, SwiftFormat and
  SwiftLint configuration, a GitHub Actions workflow, and `scripts/` for bootstrap, build,
  test and lint.
- `AGENTS.md` working agreement, with `CLAUDE.md` pointing at it.
- `SPECIFICATION.md`, carried over from the design document and now the living source of
  truth for requirements.
- `docs/mvp-scope.md` recording what the `0.1.0` pilot covers and what it deliberately
  does not.
- Architecture decision records 0001–0004.
- `UnigridsKit` Swift package with five modules — `UnigridsCore`, `UnigridsReference`,
  `UnigridsLog`, `UnigridsDesign`, `UnigridsFeatures` — and a thin `App/` target for
  iPhone, iPad and Mac.
- Domain model in `UnigridsCore`: places and their tiers, points of interest, trails,
  guide content, themes, the nine passport regions, and the America 250 seal rule.
- Deterministic stamp impressions: tilt, offset and ink density derive from a stored seed,
  so an impression renders identically every time it is drawn.
- `UnigridsReference` bundled-data loader with a hand-authored pilot seed covering all 63
  national parks by name, state and location, with deep guide content for Zion, Acadia,
  Yellowstone and Great Smoky Mountains.
- `UnigridsLog` SwiftData store for trips, visits, check-ins, stamps and weather
  snapshots, configured for the private CloudKit database.
- Map home screen: national park pins, tier styling, visited and planned badges, search,
  and a bottom card with check-in and guide actions.
- Parks directory with search and sort.
- Unigrid-style park guide: title band, at-a-glance panel, story, sights, visitor centres
  and chronology, in a grid that collapses from four columns to one with Dynamic Type.
- Passport tab: the nine regions, slot pages, a stamp sheet with date entry, and the
  America 250 overprint on stamps dated in 2026.
- Stats tab: parks and states visited, a completion ring, and visits by year.
- Visit log with manual check-in, editing and deletion.
- Offline Python pipeline skeleton (`Pipeline/`) with the fetch, match, derive, edit,
  build and package steps stubbed and documented.
- Four selectable colour palettes — Unigrid, Press, Canyon and Tidewater — and a separate
  appearance setting of Dark, Light or Automatic, both in Settings. Dark is the default.
  The choice is a per-device display preference and does not sync with the log.
- A written design system in [`docs/design-system.md`](docs/design-system.md), and
  ADR 0005 recording why colour is data in `UnigridsCore` rather than `Color` in the views.
- One icon vocabulary (`UnigridsSymbol`) in place of fifty-odd scattered symbol strings,
  with a test that every name resolves against the SDK.
- An app icon, where there was none: Zion Canyon as a true perspective heightfield under
  a blue desert sky, with three Unigrid brochures laid across it as sheets of frosted
  glass — each with its park named on the black band in Helvetica caps-and-lower-case, a
  photograph, a map panel and columns of set type. Each sheet prints its own park —
  Zion's sandstone, the Grand Canyon's strata, Yosemite's granite — so the pile reads as three
  different brochures rather than one printed three times. Light, dark and tinted
  variants plus the ten macOS sizes, all generated deterministically by
  [`Tools/IconGenerator`](Tools/IconGenerator) from the brochure system's own proportions
  and each park's own geology, and anti-aliased in the renderer itself rather than left
  to supersampling.
- Nine more app icons, one per park, switchable in Settings: Grand Canyon, Yosemite,
  Sequoia, Rocky Mountain, Olympic, Acadia, Joshua Tree, Everglades and Congaree. The
  park you pick stands behind the stack and its brochure is the one on top. iPhone and
  iPad only — macOS has no alternate app icons, and on the Mac the row says so rather
  than offering a control that would do nothing.
- The pipeline's `fetch`, `derive` and `build` steps, for one park and without an API key:
  NPS boundaries and Public Trails, USGS 3DEP elevation and OpenStreetMap roads and water,
  each versioned by date under `Pipeline/raw/` with its licence recorded beside it.
- Trail measurement in the pipeline: length, elevation gain and loss, high and low points
  and an elevation profile, every trail measured the same way from its route line and
  3DEP — resampled at 10 m, smoothed over 50 m, accumulated with a 3 m dead band so
  elevation-model noise does not read as climb. Zion comes to 44 trails and 116 km.
- Offline park packs: topo-style relief tiles rendered from 3DEP, OpenStreetMap and NPS
  trails in the style of an NPS brochure map, written as WebP in MBTiles alongside the
  measured trails, a manifest and the attribution the sources oblige the pack to carry.
- `Pipeline/out/pack-size-report.md`, which measures the pack and costs all 63 parks
  against the App Store's 4 GB limit from each park's own boundary.
- ADR 0006 recording the pack format and why.
- **Reference data built by the pipeline** rather than hand-seeded: `unigrids_pipeline
  reference` fetches the NPS Data API, NPS unit boundaries, USGS PAD-US, Wikipedia and
  Wikimedia Commons into a dated snapshot and builds 537 places — all 63 national parks,
  373 other NPS units, 76 state parks and 25 monuments, conservation areas and refuges —
  with 1,434 sights, visitor centres and campgrounds, 506 outlines and 235 photographs.
- **A detailed atlas map.** Every place is a marker whose shape is its tier and whose
  colour is its agency; national parks are outlined at every zoom and named on black
  plates, the rest outlined from regional zoom and clustered at country scale. A tap or
  click anywhere inside an outline selects the place. Region shortcuts for the Lower 48,
  Alaska, Hawaiʻi, the Caribbean and the Pacific; a map key that opens filters by tier
  and visited status; search across places and sights; a muted, hybrid or satellite base
  map.
- **An overview for every place**, opened from the map: photograph and credit, a written
  summary, figures, visit status, and check in, stamp, add to trip, open the guide and
  directions in Maps. A sheet on iPhone, an inspector beside the map on iPad and Mac.
- **Guides for all 63 national parks**, written for Unigrids and checked against the NPS
  and Wikipedia: a summary, the story, sights placed on the park map, visitor centres,
  plan your visit, chronology, safety, regulations and sources, with date established,
  area and 2025 visits for every park.
- New guide panels from the NPS's own data: a photo gallery, entrance fees and hours,
  weather and seasons, and getting there; live park alerts when the build has an NPS key.
- A park map panel with the outline and numbered sights, and **Explore in 3D**, which
  flies the camera between a park's sights.
- A page for each of the other 474 places, and written overviews for all 101 curated
  state parks, monuments and refuges.
- **Trip planning:** trips with ordered, dated stops, a route map, straight-line
  distance, reordering, a calendar (`.ics`) export, and Add to trip from every place.
  Planned places show dashed on the map, and a check-in can join a trip.
- Stats rebuilt: a national park grid, a tile map of every state and territory, headline
  figures, visits by year and by theme, the nearest unvisited park, and a share card.
- Passport rebuilt: region rows with completion, and an America 250 page.
- Export the whole log as JSON, and visits as CSV, from Settings.
- A three-panel welcome with the non-affiliation notice, shown once and available again
  from Settings.
- A Photo credits screen listing every photograph with its credit and licence, and
  attributions for USGS PAD-US, Wikimedia Commons and Open-Meteo.
- `scripts/write-secrets.sh`, which writes the gitignored `Secrets.plist` the app reads its
  NPS key from.
- ADR 0007 (one identity across every screen) and ADR 0008 (the home map wraps
  `MKMapView`).

### Changed

- **One design language on every screen.** The brochure identity now runs through the
  map, directory, trips, passport, stats and settings as well as the guides: a black band
  opens each screen, sections open with ruled caps heads, figures are set large, buttons
  and markers are square, and a palette now restyles every screen's paper and ink.
- Panels side by side in a guide share one height, so a row reads as a single sheet.
- The Parks directory can show national parks or every place.

### Fixed

- The Stamp button drew nothing. `stamp` and `stamp.fill` are not SF Symbols in any
  version, so five places — the guide's Stamp action, the place card, Trips, the visitor
  centre panel and the stamp sheet — rendered a blank space where an icon belonged. They
  now draw the app's own cancellation mark.
- Settings on the Mac reported zero visits and zero stamps. The `Settings` scene was never
  given the model container its queries read from.
- Passport stamps, agency pin colours and the park-green accent are legible in dark mode.
  Every one of the nine region inks failed WCAG AA on a dark page, four of them at even the
  lowest bar, and the accent sat at 1.95:1 where 3:1 is the minimum. Each colour now has a
  dark variant of the same hue, and a parameterised test holds every palette, scheme and
  pairing to AA so this cannot silently come back.

- Park areas no longer print spurious precision in metric locales: Acadia read
  `19,859.947893 ha` instead of `19,860 ha`.
- Measurement units now follow `.us` rather than `== .metric`. `Locale.MeasurementSystem`
  has three cases and the UK reports `.uk`, so British readers were being shown park
  elevations in feet.
- On the Mac, sheets built on a list — the stop picker, Add to trip, map filters, the
  stamp sheet and the photo viewer — collapsed to a sliver and showed nothing.
- On the Mac, the welcome screens showed a tab strip; they now page with Back and Next.
- Map camera moves requested from a search or a region shortcut landed one step late.
- A trip's map now reframes when stops are added or removed, and the stop picker leaves
  out places already on the trip.

### Notes

- Reference data is now pipeline output from a 2026-10-19 snapshot. Its provenance, photo
  policy and limits are recorded in
  `Packages/UnigridsKit/Sources/UnigridsReference/Resources/reference/README.md`.
- **Zion's offline pack is 22.2 MB** — 5,063 tiles at zoom 10–16, 256 px WebP, clipped to
  the park boundary plus a 2 km buffer. That was the pilot's open question
  (`SPECIFICATION.md` §16).
- **4 GB holds, with WebP and a per-park zoom cap: 2.2 GB for all 63 parks.** It does not
  hold at full depth everywhere (12.4 GB), and it does not hold in any PNG form at all
  (149 GB). Tile format is worth eight times over and costs nothing the eye can find; six
  Alaskan park-and-preserve units are 77 % of the national tile count. State parks cost
  about 2 MB each and are not a budget question. The brochure PDFs are the one part of the
  budget still unmeasured. The figures and what to trim are in
  [`docs/mvp-scope.md`](docs/mvp-scope.md).
- Trails and offline map packs now exist in the pipeline but not in the app: nothing reads
  a pack, so `package` deliberately does not copy one into the app's resources. The
  brochure viewer, drive times and planner conflict flags, auto-detected visits, photo
  import, widgets and the Watch app are not built. See
  [`docs/mvp-scope.md`](docs/mvp-scope.md).
- iPhone and iPad layouts compile but were checked only on macOS: the development machine
  has no iOS 27 Simulator runtime.

[Unreleased]: https://github.com/leeyenkai/Unigrids/commits/main
