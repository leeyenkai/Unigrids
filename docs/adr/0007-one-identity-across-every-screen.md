# 7. One identity across every screen

Date: 2026-10-19

## Status

Accepted. Supersedes the "two modes, and they do not mix" rule in `SPECIFICATION.md` §14,
`AGENTS.md` §6 and `docs/design-system.md` §2.

## Context

The specification split the app in two: park guides in the Unigrid style, everything else
in stock Apple design. In practice that made the app look like two products. The guides
had a voice of their own, and the map, Trips, Passport, Stats and Settings looked like any
template app. Of all the screens, the native ones were the ones a first-time user saw
first.

The owner's brief for the MVP named this directly: the app should have a distinctive
design language and keep to it, so that it does not read as generated from a template.
Stock lists with SF Symbol rows and default buttons are exactly what reads that way.

Two constraints stayed fixed. Native controls still have to behave natively — navigation,
lists, forms, sheets, search, the toolbar, keyboard and VoiceOver. And nothing may look
like the NPS's own publication: no arrowhead, no implied affiliation (`AGENTS.md` §5).

## Decision

**The brochure identity runs through every screen, on top of native structure.** The
structure stays Apple's — a sidebar-adaptable `TabView`, `NavigationStack`, `List`,
`Form`, `.searchable`, `.inspector`, sheets — and the surface is Unigrids':

- Every top-level screen opens with a **black band** (`BandHeader`): the screen's name
  reversed out in Helvetica Neue Bold, with a tracked-caps kicker beneath.
- Sections open with a **ruled head** (`SectionHead`): tracked caps over a 2 pt rule, with
  a count on the right where one helps. Hairlines (`Hairline`) divide rows.
- Figures are set large and tight over small caps labels (`FigureBlock`), the way a
  brochure's "at a glance" panel sets them.
- Geometry is **square**. Buttons are flat rectangles (`BrochureButtonStyle`); map
  markers, progress grids, the passport's region keys and the stats tile map are squares.
  Rounded pills and cards are avoided.
- A place's **tier is a shape** and its **agency an ink**, everywhere the place appears:
  a large square for a national park, a small square for another NPS site, a circle for a
  state park, a diamond for a monument or refuge (`PlaceMarker`). Filled means visited;
  dashed means planned. The map, the directory, the onboarding and the legend all draw the
  same marker.
- Longer prose is set in the system serif; data and headings in Helvetica Neue.
- Native screens sit on the palette's paper (`.paperPage()`), so a palette choice now
  reaches every screen, not only guides.

The guide grid, Dynamic Type collapse, palettes, contrast tests and the band's near-black
colour are unchanged.

## Consequences

- The app reads as one thing from the first screen. Screenshots of the map, the passport
  and a guide are recognisably the same product.
- Palettes now restyle native screens' paper and ink. The contrast tests in
  `PaletteTests` already cover every pairing these screens draw, because they use the
  same roles (`page`, `panel`, `ink`, `inkSecondary`, `rule`, `band`, `bandInk`).
- System chrome still varies by OS — toolbars, sidebars, search fields and sheet frames
  are Apple's and change with each release. That is accepted: fighting them would cost
  accessibility and platform feel for little gain.
- There is more custom drawing to maintain (`Identity.swift`, the marker views), and every
  new screen is expected to use it. `docs/design-system.md` lists the components.
