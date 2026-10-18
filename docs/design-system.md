# The Unigrids design system

How the app looks, and why. The rules here are enforced by tests where a test can see
them — `UnigridsCoreTests/PaletteTests.swift` for colour, `UnigridsDesignTests` for icons
and the SwiftUI bridge — and by review where it cannot.

## 1. The reference

The NPS Unigrid, commissioned in 1977 by NPS Publications Chief Vincent Gleason and
designed by Massimo Vignelli's office. The first brochure under the system was Clara
Barton National Historic Site in 1978; the programme won a Presidential Design Award in
1985 and is still in use.

What it actually is:

- A modular grid. The basic panel is about 4 × 8¼ in; the federal printing specification
  gives a "unigrid leaf" of 99 × 210 mm — a ratio of **1 : 2.12**.
- **Ten basic formats**, derived from a B6 base sheet divided into twelve panels per side.
  Formats are one or two panels wide and up to six panels long.
- A **black band** across the top, with titles reversed out in white Helvetica.
- Helvetica paired with Times Roman originally; Frutiger and NPS Rawlinson today.

This is homage, not reproduction. One thing is never borrowed: **the NPS arrowhead**, which
was added to the real band in 1999 and is a registered trademark (`AGENTS.md` §5). Because
it lives on the band, the band alone must never be drawn in a way that implies it.

Sources: [Unigrids](https://en.wikipedia.org/wiki/Unigrids) ·
[NPS Unigrid design specifications](https://npshistory.com/brochures/unigrid.pdf) ·
[NPS brochure history](https://npshistory.com/brochures/unigrid/index.htm)

## 2. Two modes, and where the line falls

`SPECIFICATION.md` §14 and `AGENTS.md` §6: the park guides speak Unigrid, and everything
else uses the native Apple design. They do not mix.

| | Unigrid | Native |
|---|---|---|
| Screens | Park guides only | Map, Parks, Trips, Passport, Stats, Settings |
| Surfaces | `style.page`, `style.panel` | Semantic system colours |
| Type | Helvetica Neue, system serif for prose | System fonts |
| Structure | The panel grid | Lists, forms, cards |

A palette changes the paper, the ink, the band and the app's tint. It does **not** restyle
native chrome: a themed list background would be the two modes blurring.

Three things sit on the boundary and are worth knowing about:

- **Stamps.** `StampView` draws a cancellation, but it lands on a *native* passport page.
  It may read `regionInk` and `seal` and nothing else — never `page` or `panel`.
- **Map pins.** A pin's contrast is against map tiles, which no palette controls, so a pin
  carries a stroke outline rather than relying on its tint.
- **The accent.** The tint is set once at the scene root from the palette, so native
  controls pick it up the way any Apple control does.

## 3. Colour

Colour is **data in `UnigridsCore`**, not `Color` in the view layer, for the same reason
`UnigridGrid` lives there: the contrast rule is load-bearing accessibility and a rule that
cannot be tested is a rule nobody is keeping. `ColorValue` is an sRGB triple; `Contrast` is
the WCAG 2.2 ratio; `UnigridsDesign` maps them onto SwiftUI and adds nothing.

### Roles

`page`, `panel`, `ink`, `inkSecondary`, `rule`, `band`, `bandInk`, `bandInkSecondary`,
`accent`, `onAccent`, `trail`, `water`, `seal`.

Two are easy to get wrong:

- **`onAccent` is not always white.** A dark-scheme accent has to be light enough to clear
  its page, which leaves white on it at about 2.3:1. In dark it is near-black.
- **`seal` is the same red in every palette**, varying only by scheme. A national
  commemoration is not ours to retint, and a test holds that.

### The four palettes

| Palette | Character |
|---|---|
| **Unigrid** (default) | Warm `FAF8F4` brochure stock, near-black band, park green |
| **Press** | Ink on paper. The seal red is the only colour on the page |
| **Canyon** | Sandstone and ochre |
| **Tidewater** | The blues of the brochure maps |

The band stays near-black in all four. §6 asks for a black title band with the park name
reversed out of it, and that is the one part of the Unigrid that is not ours to restyle.

### The contrast rule

Every pairing the app draws is named in `ColorRole`, and `PaletteColors.pairing(for:)`
switches over it exhaustively — so a new colour cannot be added without saying what it is
read against. The thresholds are WCAG 2.2 AA: 4.5:1 body text, 3:1 large text and UI, and
`decorative` (1:1) for hairlines that carry no information, which is listed rather than
omitted so escaping the check is a decision rather than an oversight.

Three things the suite checks that are easy to miss:

1. **Native surfaces.** The accent, the seal, the region inks and the agency tints land on
   grouped lists and map cards, not on Unigrid paper. They are measured against
   approximations of Apple's own surfaces, and clearing the lightest one clears the rest.
2. **A stamp is body text.** The site name on a 112-point stamp sets at about 10.6 points.
   Treating it as a graphic and settling for 3:1 is what left nine region inks unreadable.
3. **Dark variants keep their hue.** Lightness moves, hue does not, or the passport's
   colour-coding stops meaning anything. Held to within 12°.

Dark values are derived, not eyeballed: the light ink's own hue, lifted until it clears its
bar against the lightest surface of the scheme. That is why a dark accent looks lighter
than feels natural.

## 4. Appearance

Two orthogonal axes, both in Settings. A palette says what the paper and ink are made of;
an appearance says whether the lamp is on.

- **Appearance**: Dark (the default), Light, Automatic.
- **Palette**: the four above.

Both persist in `UserDefaults` via `@AppStorage`. This is a per-device display preference,
not the reader's data, so it deliberately does **not** sync through CloudKit with the log.
Their stored raw values are a format: renaming a case silently resets everyone's choice,
and a test says so.

Resolution is two layers, and the order matters. `preferredColorScheme` travels up to the
window as a preference and is applied back down the tree, so a single modifier that both
sets it and reads `\.colorScheme` would see the stale value on the first pass and flash the
wrong palette. `unigridsAppearance()` sets the scheme outside and resolves the style inside.

It is applied to **both** scene roots — the `WindowGroup` and the macOS `Settings` scene.
Because the choice lives in `UserDefaults` rather than in an object one of them owns, the
two always agree without anything being passed between them.

## 5. Type

| Token | Face | Used for |
|---|---|---|
| `bandTitle(_:)` | Helvetica Neue Bold 34 | The park name on the band |
| `panelHeading` | Helvetica Neue Bold 13, tracked | Panel headings, uppercased |
| `itemTitle` | Helvetica Neue Medium 16 | Sight and trail names |
| `dataLabel` | Helvetica Neue Medium 11 | At-a-glance labels |
| `dataValue` | Helvetica Neue 15 | At-a-glance values |
| `prose` | System serif, body | The story, safety, chronology |
| `caption` | Helvetica Neue 11 | Credits and captions |

Every one is `relativeTo:` a text style, so Dynamic Type works. Fonts are `static` on
`UnigridStyle`: they do not vary by palette.

**The grid collapses rather than shrinking.** `UnigridGrid.columnCount` takes a column away
as type grows (`UnigridStyle.typeScale(for:)` maps `DynamicTypeSize` onto the scale). Text
never scales down to fit — that rule is in `UnigridsCore` precisely so it is testable.

## 6. Metrics

Unigrid: `gutter` 16, `panelPadding` 18, `pageMargin` 16 — from the brochure's module.

Native: `NativeMetrics.cardRadius` 14, `chipRadius` 10, `cardPadding` 14, `rowSpacing` 12.
These replaced inline magic numbers that had drifted between screens.

## 7. Icons

One table, `UnigridsSymbol`, naming every icon by what it means rather than what it looks
like. Scattered symbol strings drift — outline here, filled there, two glyphs for one idea.

**The fill rule: outline by default; filled only for a place on a map, and for something
done.** A filled glyph reads as a pin or a tick; an outlined one reads as an action.

Symbol names are checked by `UnigridsDesignTests`, because SwiftUI renders an unknown
`systemName` as blank space instead of failing the build. This is not hypothetical:
`stamp` and `stamp.fill` were drawn in five places, including the guide's primary Stamp
action, and exist in **no** version of SF Symbols.

There is no rubber-stamp symbol at all, so the app draws its own: `CancellationMark`, the
same two-ring-and-two-rules geometry `StampView` draws at full size, scaled with
`@ScaledMetric` so it grows with the text beside it.

## 8. The app icon

> Status: specified here, built separately. See the icon generator for the implementation.

A single Unigrid leaf, full bleed, carrying its black band, backed by two offset leaves so
the mark reads as a small stack of brochures. At 1024 px the panel rules and the accent
read; at 16 px it collapses to a dark bar over a paper field with a hint of depth, which is
the Unigrid's own signature.

Geometry is derived, not eyeballed:

- Leaf proportion **99 : 210**, the federal unigrid leaf.
- A **12 × 12 module grid** on the 1024 canvas, echoing the twelve panels per side of the
  B6 sheet.
- Band depth one module of the leaf; side margins flush to the first module.
- Thin rules at module intervals below the band imply the text columns without being
  literal. One short rule in the accent.

### Constraints, not suggestions

These are the things that make a mark read as machine-generated, and the icon has none of
them: no gradients, no glow, no soft shadows, no fake 3D, no centred symmetric blob, no
literal park scenery, no mountain or tree clip-art, no lettering. Flat vector geometry,
asymmetric, grid-derived, four colours at most. Separation between leaves is a hairline
edge, never a blur.

A mark that only works at 1024 has failed. Check 16, 32, 128, 512 and 1024, in light, dark
and tinted.

## 9. Accessibility

Not optional (`AGENTS.md` §6):

- Contrast checked in both schemes — by the test suite, for every palette.
- The guide reflows with Dynamic Type, collapsing columns rather than shrinking text.
- Every pin, panel and chart carries a VoiceOver label.
- Decorative marks are `accessibilityHidden`; the label goes on the element that means
  something.
