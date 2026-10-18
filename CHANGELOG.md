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

### Fixed

- Park areas no longer print spurious precision in metric locales: Acadia read
  `19,859.947893 ha` instead of `19,860 ha`.
- Measurement units now follow `.us` rather than `== .metric`. `Locale.MeasurementSystem`
  has three cases and the UK reports `.uk`, so British readers were being shown park
  elevations in feet.

### Notes

- Reference data in this release is a hand-authored pilot seed, not pipeline output. Its
  provenance and gaps are recorded in
  `Packages/UnigridsKit/Sources/UnigridsReference/Resources/reference/README.md`.
- Trails, offline map packs, the 3D view, the brochure viewer, the planner, auto-detected
  visits, photo import, widgets and the Watch app are not built yet. See
  [`docs/mvp-scope.md`](docs/mvp-scope.md).

[Unreleased]: https://github.com/leeyenkai/Unigrids/commits/main
