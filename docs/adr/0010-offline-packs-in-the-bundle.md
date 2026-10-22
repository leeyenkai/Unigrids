# 10. Offline packs ship in the app bundle, and replace Apple's map

Date: 2026-10-23

## Status

Accepted

## Context

ADR 0006 fixed what a pack is. This one fixes how a pack reaches a phone and how the app
draws it, for the first four packs: Zion, Acadia, Yellowstone and Great Smoky Mountains,
135 MB together.

There are three ways to get a pack onto a device: download it on demand, use Apple's
background assets, or put it in the app. The first two need somewhere to download from.
`AGENTS.md` rules out a backend, and an unsigned build can't use Apple's hosted assets.

## Decision

**In the bundle, as a folder reference.**
- The pipeline's `package` step writes `App/OfflinePacks/<place-id>/` and an `index.json`.
  Each pack folder holds only its four files.
- The app target adds `App/OfflinePacks` as a folder reference, so whatever is there
  ships, with no build script.
- The folder is gitignored except its README. Packs are large and can be rebuilt from the
  raw store.
- An empty folder is a valid build: the catalogue is empty and Settings says the build
  carries no offline maps.

**Read in place, never copied.**
- `UnigridsReference.MBTilesReader` opens `tiles.mbtiles` read-only with `immutable=1`.
  The bundle is read-only and the file never changes, so SQLite takes no locks and
  writes no journal.
- One connection sits behind a `Mutex` for MapKit's tile threads. Each blob is copied
  out before its statement is finalised.

**Drawn instead of Apple's map, not over it.**
- `PackTileOverlay` sets `canReplaceMapContent`, so the Park map fetches nothing.
- It is held to the pack's rendered extent, with a zoom range taken from the manifest.
- Past the pack's deepest zoom, the deepest tile is enlarged by up to two levels, so the
  map can come close without going blank.
- The pack's trails file is not read. The Park map draws the same catalogue trails as
  every other screen, so a trail has one length and one line everywhere.

**Where it opens.**
- From a guide's map panel and its toolbar.
- From a trail's page, with that trail in focus.
- In place of the 3D explorer when `NWPathMonitor` reports no connection, since Apple's 3D
  needs one.

**Credit.** The tiles carry their credit on the map itself: USGS 3DEP, OpenStreetMap
(ODbL) and NPS trails. Settings › Attributions says where OpenStreetMap is used.

## Consequences

- The app grows by the size of its packs. Four parks cost 135 MB.
- At ADR 0006's measured average, all 63 parks at their area-based depth would cost about
  12 GB, well past what a download should be. Shipping every park needs on-demand
  resources or Background Assets, which need signing. That's a later decision.
- A pack updates with an app release, like the rest of the reference data (ADR 0002).
- WebP decoding is checked on macOS with ImageIO. MapKit decodes tile data the same way
  on both platforms. A pipeline change to a different tile format would need this ADR
  revisited.
