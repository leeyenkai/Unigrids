# IconGenerator

Draws the Unigrids app icon and its nine alternates, and writes them into
`App/Unigrids/Assets.xcassets`: thirteen PNGs for the shipping icon in
`AppIcon.appiconset`, three for each alternate in `AppIcon-<park>.appiconset`, and the
`Contents.json` that indexes each set.

```bash
cd Tools/IconGenerator && swift run -c release IconGenerator --all            # all ten sets
cd Tools/IconGenerator && swift run -c release IconGenerator                  # Zion only
cd Tools/IconGenerator && swift run -c release IconGenerator --park olympic --preview /tmp/look
```

`--park` takes a `Scene` raw value: `zion`, `grandCanyon`, `yosemite`, `sequoia`,
`rockyMountain`, `olympic`, `acadia`, `joshuaTree`, `everglades`, `congaree`. An unknown
name is an error rather than a silent fall back to Zion. `--preview` writes a handful of
sizes and leaves the asset catalogue alone; a directory argument writes there instead.
Build in release: the terrain march is a few million samples per image and a debug
build takes minutes over what release does in seconds.

No dependencies: CoreGraphics and ImageIO are both in the macOS SDK. The output is deterministic — running it
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

Ten parks are built. **Zion** is the default and what ships; the other nine are alternate
icons the reader can choose in Settings (iOS and iPadOS only — macOS has no alternate
app icons).

### How it is rendered

The icon follows the system's own material language rather than the print idiom the app's
guides use inside. Three earlier attempts did the opposite — flat fills, hard edges, no
shading, on the principle that a brochure is printed and printed things do not glow — and
each read as a diagram rather than an icon.

| | |
|---|---|
| **Glass** | A real Gaussian blur through CoreImage, not a white overlay. Glass blurs what is behind it, tints it towards white and casts a shadow. Leaving any of the three out is what makes an overlay look like a sticker. |
| **Terrain** | A real heightfield in perspective, rendered by the classic voxel-space method: march away from the camera, project each sample's height to a screen row, and keep a y-buffer per column so nearer ground paints over what is behind it. True occlusion, true convergence, a few million cheap operations, and deterministic to the byte — which a GPU path would not be. See `Terrain.swift`. |
| **Ground** | Procedural, not drawn: deterministic value noise shaped per park, at **two to four octaves and a large feature size**. A full fractal gives detail nobody sees — noise at 1024 px, mud at 64 — and a handful of big landforms is what the eye actually uses to read a canyon. The crests are one of three kinds: **rounded** swells for ice-scoured granite and lowland; **rims**, where the noise is folded once and tops out at a level line, for canyon country; and **peaks**, folded octave by octave so summits come out at different heights, for a mountain range. See `Heightfield.swift`. |
| **Sky** | A real blue overhead paling to the horizon, with cloud banded across it from the same value noise the ground uses — stretched wide and flat and kept out of the horizon. A sky with nothing in it is the quickest way to make a landscape look unfinished. |
| **Vegetation** | Two kinds. Ground cover is a colour: cottonwood on Zion's floor and scrub on every bench and talus fan that will hold it, which is most of the colour there that is not rock. Plants that *are* the park — Joshua trees, giant sequoia, bald cypress, fir, hardwood hammocks — are drawn as objects standing on the ground. Ground cover is **thresholded into patches, not dialled in as a wash**: green blended at half strength over orange sandstone is olive, and olive is mud. |
| **Plants** | Each is an outline in its own frame — a fir's drooping courses, a sequoia's buttressed column and clumped crown, a Joshua tree's arms and dagger-leaved heads — rasterised by **four-by-four supersampling of that outline** and lit from the same side as the land. Foliage edges and interiors come from noise: a regular scalloped edge with an even fill is a cloud from a children's book. They are **occluded pixel by pixel**: the terrain march records how far away every pixel it paints is, and a plant is drawn only where it stands nearer, so a tree behind a ridge shows exactly the part that clears it. The first version filled whole-pixel boxes with no light, and at icon size that is a sprite from an old video game. Nothing roots on a wall. The trees a park is named for or known by are also **placed by hand** (`Scene.specimens`), where the brochures will not cover them. |
| **Shading** | Rock colour comes from **altitude**, so the beds really are the strata and a rim is a different colour from the wall under it. Both the bands and the light are **continuous**: an earlier version had crisp bed edges and light quantised into four steps, and both stair-stepped, because a boundary that resolves inside one row has to land on a row edge and adjacent columns put it on different rows. The simplicity comes from the form being simple instead. |
| **Light** | One direction, top-left. Faces carry gradients along it; the sun is a soft radial bloom with no disc, because a drawn sun is the fastest way to make a landscape look like clip-art. |
| **Resolution** | Everything is drawn at 2x (4x at 256 px and below) and resampled, at every size. Large sizes need it as much as small ones, because the cover photograph magnifies whatever the terrain hands it. |
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

Ten of them, and the reader picks which one the app wears. The park's own land stands
behind the stack and **its brochure is the one on top**, with the next two parks round
the list behind it — so every variant shows a different trio and no variant shows the
same park twice. Each park's terrain is rendered once and reused by whichever sheet
needs it, so three sheets cost three terrains rather than nine.

A park is a row in a table, not a function: `LandForm` in `Heightfield.swift` says how
much relief there is, how large the landforms are, what the crests do, whether the rock
beds, where the low ground is, where the water stands, where the snow lies, what grows,
where the camera stands and whether a landmark rises out of the rest. `Scene.swift` says what
colour it all is and how much of it carries plants. Ten bespoke height functions would
have been ten places to get the same thing subtly wrong.

Three things that have to be relative to the park rather than fixed, each of which broke
a park when it was not:

- **The camera.** A park whose relief rises past it is a wall across the frame; one far
  below it is a distant smudge in the haze. Olympic and Rocky Mountain were both, in turn.
- **The low ground.** Every park needs some, or the camera has nowhere to stand — and
  where it runs decides the framing. A canyon runs *away* from the camera and puts a wall
  on each side, which is right for Zion and wrong for Rocky Mountain, whose own view is
  an open valley floor with the range standing across the back of it; that park's low
  ground runs *across* the frame instead. The sea does it for Acadia, and the waterline
  itself for the Everglades and Congaree.
- **The strata and the treeline.** Both were normalised against one park's relief, so a
  taller park put all its ground in the palest bed and came out white to the horizon.

And vegetation is per park: one rule for all of them turned Joshua Tree into pasture. A
desert is defined by what will not grow on it as much as a rainforest is by what will.

**Acadia.** The Park Loop shore: pink granite stepping down in ledges into the Atlantic,
spruce to the brink, surf on the rocks, islands standing off the coast, and Cadillac's
broad summit behind it all. A sea level on its own floods the hollows between hills and
never makes open water, so this park has a **coastline**: land on one side, the land cut
away on the other, and the shore broken by noise finer than the land's own so it comes out
as points, coves and rocks rather than a beach. Bare granite to the reach of the spray,
rockweed at the tideline, paler water over the ledges, and white water where it is shallow
enough to break. The islands stand on no plinth: on one, each was a drum with a dome on
top — a cake on a plate.

**Zion.** The Virgin River cut a slot a half-mile deep through Navajo Sandstone. Blunt
summits with long talus shoulders, and the canyon notched between two walls. The rock is
banded — white upper beds for want of iron, pink middle, red-brown lower with hematite.

**Yosemite.** The valley as it opens from Tunnel View: granite walls straight up out of a
flat, forested floor, and **Half Dome** at the head of it. The walls are the valley's own
cross-section, cut as a glacial U — a high exponent on the canyon's profile — and not
landmarks; drawn as cut domes, El Capitan and Cathedral Rocks were two more copies of
Half Dome's outline, and three of it is none of it. Half Dome's face looks almost straight
across the line of sight, because that is the only way the cut shows in the skyline: cut
the front off a dome and its back half still spans the full width, so the outline stays a
whole dome. It is much broader than tall, and stands well clear of the walls, as it does.
Water streaks run down every steep face — keyed on position rather than on the row, so
they fall straight down it.

**Grand Canyon.** Zion's method at a larger scale and stepped rather than sheer: rim to
river through cream, pale, rust and red beds, with the Colorado confined to the floor of
the channel the canyon cut.

**Sequoia and Kings Canyon.** The Giant Forest. Two giant sequoias close enough that only
their bark shows, framing the stack — cinnamon going to rust in the sun, deeply furrowed,
with fire scars at the foot — and two more further off with their crowns in view. Between
them a forest of fir with every few trees another giant, and the granite of the Great
Western Divide behind. The trunk barely tapers, which is most of what a giant sequoia
looks like, and its crown is one dense mass with clumps standing out from it: drawn as
separate puffs on sticks, it was a lollipop.

**Rocky Mountain.** An open valley of spruce and fir, and a range across the back of it:
granite summits at different heights, a band of alpine tundra under them, snow wherever the
ground is flat enough to hold it. No landmark. Four attempts built the range out of
individual cones, and each came out as a row of props — a curve of one variable has the
same silhouette from every bearing, and a cone steep enough to fit the frame is a spike.
The noise, folded per octave, makes a range that is jagged at every scale.

**Olympic.** Rainforest to the crests of the ridges, and one snow-covered stratovolcano
standing over them, truncated at a crater rim. **This is not the park's own geology**:
Mount Olympus is a glaciated peak of uplifted sea-floor rock, not a volcano. The volcano is
an artistic choice, drawn at the owner's direction as the silhouette the Northwest is known
by. Its proportions matter more than anything else in the mark: twice as wide at the foot
as it is tall, set far enough back to fit, and flat-topped. Narrower, it is a spike;
rounded on top, it is a shape no one wants on a home screen.

**Joshua Tree.** Monzogranite weathered into piles of rounded boulders on a flat desert
floor, with the trees standing on it — four placed by hand where the stack leaves room, the
rest scattered on the flats. Their heads are ragged balls of dagger-shaped blades swept
upwards; a few regular round lobes made daisies. No green wash: one vegetation rule for
every park once turned it into pasture.

**Everglades.** Almost no relief at all. The sky and the sawgrass do the work, and the
only things standing out of it are the hardwood hammocks on their tree islands.

**Congaree.** A floodplain under bottomland forest, with bald cypress standing in the
water. The water is the floor and the forest is the subject.

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
| `icon-1024-dark.png` | iOS `luminosity: dark` — night in the park, not an inversion. The rock keeps its hue, and the frost thins so the sheets read as lit glass rather than as grey slabs. |
| `icon-1024-tinted.png` | iOS `luminosity: tinted`, greyscale for the system to tint |
| `icon-mac-{16,32,128,256,512}[@2x].png` | the ten macOS sizes |

That is the shipping set, in `AppIcon.appiconset`. Each alternate in
`AppIcon-<park>.appiconset` carries only the three iOS files: macOS has no alternate app
icons, so Mac sizes for them would be dead weight in the bundle. The set names must match
the `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` build setting and
`AppIconChoice.alternateIconName` in `UnigridsCore`; `AppIconChoiceTests` holds the
latter to the list.

Below 64 px the fan drops from three sheets to two and the accent block comes off: at that
size they are a pixel of noise each.

The output is deterministic — the CoreImage blur runs on the software renderer precisely so
that it is, rather than varying with whatever GPU is in the machine.
