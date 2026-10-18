# 5. Colour is data in the core, resolved into the environment

Date: 2026-10-18

## Status

Accepted

## Context

`UnigridStyle` was a caseless enum of hardcoded `Color(hex:)` statics. Scheme-dependent
colours were `static func page(_ scheme: ColorScheme) -> Color`, and fifteen call sites
each declared `@Environment(\.colorScheme)` purely to pass the scheme back in. There was
no seam for a user-selectable theme, and no way to test any of it.

That second part mattered more than it looked. `AGENTS.md` §6 requires contrast "checked in
both light and dark", and nothing checked it. Measuring the existing values found roughly
twenty that were wrong in dark mode: the park-green accent at 1.95:1 against a grouped list
background where 3:1 is the floor, the seal red at 2.73:1, and **all nine** passport region
inks failing 4.5:1 on a dark page — four of them below even 3:1. A navy cancellation on a
near-black page is invisible, and it had shipped that way because the only thing that could
have caught it was a test that could not be written: SwiftUI's `Color` exposes no
components to measure.

Two further constraints shaped the design. `Theme` is already a domain type in
`UnigridsCore` — a content tag on a place (geology, ecosystem, history) that is decoded
from bundled JSON — so the visual system could not have that name. And the app had no
persisted preference of any kind; a theme would be the first.

## Decision

**Colour values and the WCAG rule live in `UnigridsCore`, as Foundation-only data.**
`ColorValue` is an sRGB triple with a relative-luminance; `Contrast` is the ratio and the
AA thresholds; `Palette` is the four palettes; `ColorRole` names every foreground-on-
background pairing the app actually draws. `UnigridsDesign` maps these onto SwiftUI and
adds nothing of its own.

This follows a precedent set twice already. `UnigridGrid` keeps the column-collapse rule —
the other load-bearing accessibility rule — in the core so it is testable without a view,
and `PassportRegion.inkHex` was already a `String` in the core bridged to a `Color` in the
design layer. Colour is the same shape of problem.

**`UnigridStyle` becomes a `struct` resolved from (palette, effective scheme), read from
the environment.** Fonts and metrics stay `static` on it: they do not vary by palette, and
making them instance members would have churned twenty-five call sites for nothing. It is
`Sendable` and `Equatable` — the latter is load-bearing, because SwiftUI compares
environment values to decide what to invalidate.

**The preference is two `@AppStorage` values, not an `@Observable` store.** The state is
two enum cases with no derived state, nothing async and nothing to validate. A store would
have to be constructed in `UnigridsApp` and threaded into both scenes, which is exactly the
plumbing `UserDefaults` makes unnecessary, and it would be a second source of truth needing
write-back to survive launch. It is a per-device display preference, so it does not sync
through CloudKit with the log.

**Resolution is two layers.** `preferredColorScheme` travels up to the window as a
preference and is applied back down the tree, so a modifier that both sets it and reads
`\.colorScheme` sees the stale value on the first pass. The outer layer sets the scheme;
the inner one resolves the style and sets `.tint`.

## Consequences

The contrast suite is now the gate: every palette × scheme × role, plus region inks and
agency tints against native surfaces. Adding a colour without saying what it contrasts
against is a compile error, because `pairing(for:)` switches exhaustively over `ColorRole`.
Adding a palette means adjusting hexes until the suite passes — that is the suite working,
not an obstacle.

Native screens now take the accent through `.tint` rather than reading a colour. Note that
`Color.accentColor` does *not* read a `.tint` modifier — it reads the asset catalogue — so
the `ShapeStyle` form is the one to use.

`AccentColor.colorset` keeps a static value (now with a dark variant) and necessarily
diverges from a non-default palette. An asset catalogue is resolved at build time, so it
governs only what the app cannot reach: the Settings-app row, the share sheet, a future
widget. Unsetting `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME` would fall back to
system blue, so it stays.

The persisted raw values (`"dark"`, `"unigrid"`, …) are now a stored format on real
devices. Renaming a case resets the reader's choice silently; a test names that cost.

An `@Observable` appearance store becomes worth revisiting the day the preference is
derived from something else — a per-park palette, or an automatic switch at sunset.
Recorded in `SPECIFICATION.md` §17.
