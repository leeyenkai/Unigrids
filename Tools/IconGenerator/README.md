# IconGenerator

Draws the Unigrids app icon and writes
`App/Unigrids/Assets.xcassets/AppIcon.appiconset` — thirteen PNGs and the
`Contents.json` that indexes them.

```bash
cd Tools/IconGenerator && swift run                        # what ships: Zion
cd Tools/IconGenerator && swift run -- --landscape yosemite
cd Tools/IconGenerator && swift run -- /tmp/look --preview  # a few sizes, catalogue untouched
```

No dependencies: CoreGraphics and ImageIO are both in the macOS SDK.
Pass a directory to write somewhere else. The output is deterministic — running it
twice produces byte-identical files, so a regeneration that changes nothing shows up
as an empty diff.

It lives here rather than in `Packages/UnigridsKit` so the app package stays free of a
build tool it never links, and it hardcodes its six colours rather than importing
`UnigridsDesign`: an icon that silently changed when the palette was refactored would
be worse than a duplicated constant.

## The mark

A national park fills the tile — sky, a low sun, curved ridges receding into haze — and
three Unigrid brochures lie fanned across the foreground as sheets of frosted glass, the
park showing blurred through them. The top of each sheet carries the black band, which is
the one opaque thing in the mark and the one that says Unigrid.

Two parks are built, selected with `--park`; **Zion** is the default and what ships.

### How it is rendered

The icon follows the system's own material language rather than the print idiom the app's
guides use inside. Three earlier attempts did the opposite — flat fills, hard edges, no
shading, on the principle that a brochure is printed and printed things do not glow — and
each read as a diagram rather than an icon.

| | |
|---|---|
| **Glass** | A real Gaussian blur through CoreImage, not a white overlay. Glass blurs what is behind it, tints it towards white, catches a rim light along its edges and casts a shadow. Leaving any of the four out is what makes an overlay look like a sticker. |
| **Terrain** | A real heightfield in perspective, rendered by the classic voxel-space method: march away from the camera, project each sample's height to a screen row, and keep a y-buffer per column so nearer ground paints over what is behind it. True occlusion, true convergence, a few million cheap operations, and deterministic to the byte — which a GPU path would not be. See `Terrain.swift`. |
| **Ground** | Procedural, not drawn: deterministic value noise shaped per park, at **two or three octaves and a large feature size**. A full fractal gives detail nobody sees — noise at 1024 px, mud at 64 — and a handful of big landforms is what the eye actually uses to read a canyon. Zion gets a meander carved through it; Yosemite a glacial U and one sheared dome. See `Heightfield.swift`. |
| **Sky** | A real blue overhead paling to the horizon, with cloud banded across it from the same value noise the ground uses — stretched wide and flat and kept out of the horizon. A sky with nothing in it is the quickest way to make a landscape look unfinished. |
| **Vegetation** | Cottonwood on the floor and scrub on every bench and talus fan that will hold it, which is most of the colour in either park that is not rock. **Thresholded into patches, not dialled in as a wash**: green blended at half strength over orange sandstone is olive, and olive is mud. |
| **Shading** | Rock colour comes from **altitude**, so the beds really are the strata and a rim is a different colour from the wall under it. The bands are **crisp at their boundaries** and the slope shading is **quantised into four steps** — which is the whole balance the icon is struck at. Smooth shading over a detailed surface reads as a photograph of rock; flat silhouettes read as a diagram. Simple form plus banded colour plus stepped light sits between the two. |
| **Light** | One direction, top-left. Faces carry gradients along it; the sun is a soft radial bloom with no disc, because a drawn sun is the fastest way to make a landscape look like clip-art. |
| **Resolution** | Everything is drawn at 4x and resampled, at every size. Large sizes need it as much as small ones, because the cover photograph magnifies whatever the terrain hands it. |
| **Anti-aliasing** | Six separate things, all of them needed. A skyline lands between two rows far more often than on one, so the row it lands in is painted **in proportion to how much of it the rock covers**. The row below it is then **repainted solid** when the next sample covers it — left at its partial coverage, every old skyline survives as a pale line and the face comes out banded. And a span is **graded** from the previous sample's colour to this one's, because one span can cover many rows of a steep face and filling it flat snaps every strata boundary to the span's edge, which is what put sawteeth along the bands. A column's *first* span is the exception: there is nothing behind it to grade towards, and seeding one fringes the bottom edge in that colour. Every other input — **slope, vegetation and haze** — is interpolated across the span the same way, because each is a property of a *sample* and anything constant across a span bands, then stairs where the span edges shift between columns. And the march is fine enough that **a span is about a row deep**. |
| **Dither** | Even then a near-level boundary quantises to whole rows, and every column marching the same ladder of distances means it crosses the same rung for a run of columns and then drops — a regular staircase, and regularity is what the eye picks out. Each column therefore starts **a fixed fraction of a step along**, from a hash of its index. The boundary frays instead of stepping, and the fraying resolves under the 4x downsample into a clean edge. Deterministic, because the offset is a hash and not a random number. |
| **Seams** | Two antialiased edges a fraction of a pixel apart leave a hairline of whatever is between them. The band is **intersected** with the sheet rather than clipped to it, so there is one edge instead of two stacked; and the fill that throws each sheet's shadow is **inset** a couple of pixels, so its own edge hides under the sheet instead of fringing the top of it. |

### The sheets

Three brochures opened flat and laid down in a pile stepping back and to the left, each
carrying a real cover: the black band with the park's name and designation, a photograph
of the park across the measure, a map panel beside it, and three columns of set type
under both.

The name is set in **Helvetica Medium, caps and lower case** — "Zion", not "ZION". The
federal specification is explicit about C/lc, and all-caps is the thing that most quickly
turns a homage into a pastiche. It is optically centred on the cap rather than the em box,
because the em box reserves descender space the word barely uses and the name rides high.

The type columns are **individual rules of unequal length**, not solid blocks. A block is
a placeholder; a run of thin lines ending raggedly is what a column of type looks like
from across a room, which is the distance an icon is always read from.

The band carries the park and its state and nothing else. A real one also carries the
agency and the Department of the Interior, and this one deliberately does not: `AGENTS.md`
§5 forbids implying affiliation, and that line would.

Each sheet is built in its own coordinates and put through one shared transform, so the
band, the columns, the accent rule and the type all land correctly however far the sheet
is rotated. Positioning the band by trigonometry against a rotated sheet left it floating
in the middle of the leftmost one.

Two details that read wrong if you get them wrong: the accent block is **square**, because
a rounded one reads as the chip on a bank card, and the sheets carry **no outline**, because
a stroke around a pane of glass is a sticker's edge rather than a sheet's.

### The parks

Each sheet in the stack prints **its own** park, so the pile reads as three different
brochures rather than one printed three times. Each park's terrain is rendered once and
reused by whichever sheet needs it, so three sheets cost three terrains rather than nine.

**Acadia.** Low granite domes standing out of the Atlantic. Nothing ridged or terraced:
the rock was ground down under ice and then drowned at its edges, so the land is a set of
rounded swells with the sea coming in between them, dark spruce on every shoulder, and
Cadillac standing higher than the rest. It is the one park of the three whose colour is
mostly not its rock, which is exactly why it belongs in the stack.

**Zion.** The Virgin River cut a slot a half-mile deep through Navajo Sandstone. Blunt
summits with long talus shoulders, and the canyon notched between two walls. The rock is
banded — white upper beds for want of iron, pink middle, red-brown lower with hematite.

**Yosemite.** Granite domes out of a glacial U: rounder crowns, one sheer face where Half
Dome was sheared, and a long flat rim between the walls. "Salt-and-pepper" stone, light
quartz and feldspar against dark biotite and hornblende, over meadow and pine.

## Rules the mark is held to

- Shading follows one light and stays subtle. Wide tonal swings read as plastic and a hard
  specular highlight reads as glass of the wrong kind.
- No clip-art. The land is a reduction: every field in it is a ridge, a bed or a floor
  that is there. If a shape can go without losing a fact, it goes.
- Type only where it can be read: the park names come off below 128 px, where a name is a
  smear along the band and worse than no name at all.
- **Terracing lives in the colour, not the geometry.** Treads wide enough to see are
  treads whose edges run nearly along the line of sight, and those alias into a sawtooth
  no amount of supersampling removes. The strata are drawn in the palette instead, where
  they cost nothing and cannot step.
- **No NPS arrowhead** (`AGENTS.md` §5) — a registered trademark. The band is a plain
  rectangle and carries nothing.

## What gets written

| File | Use |
|---|---|
| `icon-1024.png` | universal iOS, light |
| `icon-1024-dark.png` | iOS `luminosity: dark` — night in the park, not an inversion. Both parks are dark-sky parks and the rock keeps its hue; the frost thins so the sheets read as lit glass rather than as grey slabs. |
| `icon-1024-tinted.png` | iOS `luminosity: tinted`, greyscale for the system to tint |
| `icon-mac-{16,32,128,256,512}[@2x].png` | the ten macOS sizes |

Below 64 px the fan drops from three sheets to two and the accent block comes off: at that
size they are a pixel of noise each.

The output is deterministic — the CoreImage blur runs on the software renderer precisely so
that it is, rather than varying with whatever GPU is in the machine.
