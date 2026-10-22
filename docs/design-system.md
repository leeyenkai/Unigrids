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

## 2. One identity, on native structure

Until the MVP the guides spoke Unigrid and every other screen was stock Apple design.
[ADR 0007](adr/0007-one-identity-across-every-screen.md) replaced that split: the
brochure identity now runs through every screen, laid over native structure.

| | Structure (Apple's) | Surface (Unigrids') |
|---|---|---|
| Navigation | Sidebar-adaptable `TabView`, `NavigationStack`, `.inspector`, sheets | `BandHeader` at the top of every screen |
| Content | `List`, `Form`, `.searchable` | `SectionHead`, `Hairline`, `FigureBlock`, `PlaceRow` |
| Controls | System toggles, pickers, menus | `BrochureButtonStyle` for actions |
| Surfaces | — | `.paperPage()`: the palette's `page`, with list backgrounds hidden |
| Type | System fonts in controls | Helvetica Neue for headings and data, system serif for prose |

The components live in `UnigridsDesign/Identity.swift`:

- **`BandHeader(title, kicker:)`** — the black band, title reversed out, tracked-caps
  kicker. Every top-level screen and every trip opens with one.
- **`SectionHead(title, count:)`** — tracked caps over a 2 pt ink rule.
- **`Kicker`**, **`Hairline`** — small caps labels and 1 pt dividers.
- **`FigureBlock(value:label:)`** — a big tight figure over a caps label, as the "at a
  glance" panel sets one.
- **`BrochureButtonStyle(.primary | .secondary | .onBand)`** — flat, square, no capsule.
- **`SitePin(type:tier:status:)`** — a place's pin, shared by the map (drawn there in
  layers by `AtlasMarkerView`), the key, directory and search rows, stats and onboarding.
  Three cues, each read on its own ([ADR 0009](adr/0009-pins-coloured-by-kind-of-place.md)):
  **colour and pictogram are the kind of place, shape is who runs it.** The pin is solid:
  the colour filled, a white pictogram reversed out of it, a white keyline round it. A
  visited place carries a green tick at the lower right; a planned one a dashed ring.

  | Tier | Shape | Pin | Glyph | Plain marker |
  |---|---|---|---|---|
  | National park | Square, black, white star | 26 pt | 14 pt | 14 pt |
  | Other NPS site | Square | 22 pt | 12 pt | 10 pt |
  | State park | Circle | 23 pt | 12 pt | 11 pt |
  | Other public land, landmarks, byways | Hexagon, point up | 25 pt | 12 pt | 12 pt |

  Colours are `SiteInk`, one per family of site types:

  | Family | Types | Pin |
  |---|---|---|
  | National park | National parks | `1A1A1A` black |
  | Monument | NPS, BLM and Forest Service monuments | `B3243A` crimson |
  | History | Historic sites, battlefields, memorials | `7A4B2A` brown |
  | Water | Seashores, recreation areas, rivers | `1A72B8` blue |
  | Wild land | Forests, grasslands, preserves | `2F7A32` green |
  | Refuge | Wildlife refuges | `00827E` teal |
  | Conservation | BLM conservation areas | `9A7A0A` amber |
  | Landmark | National Natural Landmarks | `B02E8C` magenta |
  | State park | State parks | `6447C2` violet |
  | Road | Parkways, scenic byways | `D2600A` orange |
  | Other | Other NPS sites | `767676` grey |

  Pins keep these values in both schemes, because the keyline does the work against a
  dark map. Outlines, routes and list tints use `SiteInk.value(_:)`, lifted in the dark
  scheme to clear 3:1 (national parks turn near-white there, since a black outline
  vanishes on a dark map); over satellite imagery the map always uses the dark values.
  Tests hold a white pictogram to 3:1 on every pin, every colour to 30 ΔE (CIE76) from
  every other, and every pictogram to being different. The eighteen pictograms are SF
  Symbols named in `UnigridsSymbol.site(_:)`.
- **`PlaceMarker(tier:tint:status:)`** and **`MarkerShape`** — the pin without its
  pictogram, for lists too small for one: filled when visited, hollow when not, dashed
  when planned. `KeySwatch` is the same shape keylined, for the key's chip.
- **`AgencyInk`** — an agency's colour. No longer on pins or outlines; it colours the
  national park grid in Stats.
- **`.sheetSize(width:height:)`** — gives a sheet a size on the Mac, where a `List` or
  `ScrollView` sheet otherwise collapses. iOS ignores it.

Things worth knowing at the edges:

- **Stamps.** `StampView` reads `regionInk` and `seal` only, never `page` or `panel`, so a
  cancellation looks the same on every palette.
- **Map markers.** A marker's contrast is against map tiles, which no palette controls, so
  every pin carries a white keyline and a soft shadow rather than relying on its fill.
  National parks wear a black label plate with white type, the band in miniature, under
  a black pin. Clusters are round black counts, so they never read as a national park;
  national parks gathered at country scale are a starred black square with the count.
- **Detail by zoom.** The map shows what it can draw legibly and no more: overview
  outlines and national park pins across the country; pins for other large lands, and
  pictograms inside pins, from regional zoom; alert badges, US highways and Amtrak
  stations closer in. The thresholds are latitude spans in `MapDetail`, tested in Core.
- **Lines on the map.** Lines borrow the road-atlas convention rather than a palette:
  Interstates blue with a light casing, US routes neutral grey so they sit under the
  places, Amtrak a dark line with white dashed ties, byways a solid line in the road
  colour. Line colours live in `TransportStyle` with a light and dark value each, because
  they are read against map tiles, not paper.
- **The accent.** The tint is set once at the scene root from the palette, so system
  controls pick it up the way any Apple control does.
- **Guide panels in a row share a height**, so a row reads as one sheet of equal panels.
  Order still never changes to fill a gap (`UnigridGrid.rows`).

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

1. **Native surfaces.** The accent, the seal, the region inks and the site tints land on
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

> Built by `Tools/IconGenerator`, which has the full construction notes.
> `swift run -c release IconGenerator --all` there regenerates all ten icon sets,
> deterministically.

A national park fills the tile, rendered as a perspective heightfield, and three Unigrid
brochures lie across the foreground as sheets of frosted glass with the park showing
blurred through them. Each sheet prints **its own** park, so the pile reads as three
different brochures rather than one printed three times.

**Ten parks are built, and the reader picks one in Settings** — Zion, Grand Canyon,
Yosemite, Sequoia, Rocky Mountain, Olympic, Acadia, Joshua Tree, Everglades and Congaree.
The chosen park's land stands behind the stack and its brochure is the one on top. Zion
ships as the app's own icon; the other nine are alternate icons.

One of them departs from its park on purpose. Olympic's icon stands a stratovolcano over
the rainforest, and Mount Olympus is not a volcano — it is a glaciated peak of uplifted
sea-floor rock. The volcano was the owner's call, as the silhouette the Northwest is known
by. It is an icon, not a claim, and nothing in the app's data says otherwise; it is
recorded here and in the generator so that nobody mistakes it for one.

Alternate icons are a UIKit feature, so the picker works on iPhone and iPad and says so
on the Mac rather than offering a control that would do nothing. The names appear in
three places that have to agree — the appiconset folders, the Xcode target's
`ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`, and `AppIconChoice` — and a mismatch
fails silently at runtime, so `AppIconChoiceTests` pins the raw values.

### The icon does not follow the print rules, on purpose

Inside the app the Unigrid is flat by rule: printed paper, hard edges, no shading. **The
icon is the one place that rule is suspended.** The system's own icons are lit, glassy,
curved objects, and a mark that refuses all of that does not read as austere beside them —
it reads as unfinished. So the icon gets a real Gaussian blur behind its glass, gradients
along a single light, curved landforms and soft shadows.

It still refuses gloss, hard specular highlights and clip-art.

### Where it sits between flat and rendered

The terrain is a true perspective heightfield, so it converges and occludes like ground
rather than like stacked cut-outs. But it is deliberately **not** a render: two to four
octaves of noise instead of a full fractal, a few big landforms rather than many small
ones, and the strata carried by colour rather than by modelled ledges. Flat silhouettes
read as a diagram; a detailed surface under smooth shading reads as a photograph. This
sits between them, and that is the whole intent.

### The one place the app sets type in an icon

Each brochure carries its park's name reversed out of the black band — the chosen park on
the front, two others behind it — in caps and lower case, as the federal specification
sets it, and in the same Helvetica Neue the guides use, flush with the first grid
module as a real Unigrid sets it. Under the band, three columns of set type on the
brochure's grid. Without them the sheets were blank panels; §7's "no lettering" rule covers
the app's iconography and stops at the app icon.

Names come off below 128 px, where they are a smear rather than a word.

A mark that only works at 1024 has failed. Check 16, 32, 128, 512 and 1024, in light, dark
and tinted; below 64 the fan drops to two sheets.

## 9. Accessibility

Not optional (`AGENTS.md` §6):

- Contrast checked in both schemes — by the test suite, for every palette.
- The guide reflows with Dynamic Type, collapsing columns rather than shrinking text.
- Every pin, panel and chart carries a VoiceOver label.
- Decorative marks are `accessibilityHidden`; the label goes on the element that means
  something.
