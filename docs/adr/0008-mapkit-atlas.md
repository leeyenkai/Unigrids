# 8. The home map is MKMapView, wrapped

Date: 2026-10-19

## Status

Accepted

## Context

The MVP map has to carry 537 places and 506 outlines at once (`SPECIFICATION.md` §5):
every national park outlined at country scale, the other 470-odd places as markers that
cluster, outlines for those appearing from regional zoom, tier shapes and agency inks on
every marker, and a tap *inside an outline* — not only on a pin — selecting the place.

SwiftUI's `Map` was the first choice and is still used for the small maps (a guide's park
map, a trip's route, the 3D explorer). For the home map it fell short on three counts:

- **Clustering.** `Map` has no annotation clustering. Four hundred NPS-site pins at
  country scale are an unreadable carpet.
- **Hit-testing outlines.** `MapPolygon` content is not tappable, and `MapReader` gives a
  coordinate for a tap but no way to know whether the tap landed on a marker first.
- **Volume.** Re-diffing hundreds of `Annotation` views and polygons in a `MapContent`
  builder on every camera change was slow enough to drop frames on a Mac.

## Decision

**The home map is `AtlasMapView`, a `UIViewRepresentable` / `NSViewRepresentable` around
`MKMapView`, with a `@MainActor` coordinator.**

- Markers are `MKAnnotationView`s that draw the tier shape in Core Animation layers
  (`AtlasMarkerView`), so the marker on the map is the same `MarkerShape` the rest of the
  app draws. National parks never cluster and have `.required` display priority; every
  other place clusters under one identifier into a square `AtlasClusterView` with a count.
- Outlines are `MKMultiPolygon` overlays, added and removed as the camera moves: national
  parks at every zoom, other places only below a latitude span of 14° and only where they
  intersect the visible region (`MapDetail`, in `UnigridsCore`, tested).
- A tap or click is hit-tested in the coordinator: markers first (within 18 pt), then the
  smallest outline containing the point, using the even-odd test in `PlaceBoundary`.
- Camera moves are requests (`AtlasCameraRequest`) with an identity, applied on the next
  main-queue turn so a move requested during a SwiftUI update is not applied one step
  late.
- Geometry, filters and detail rules live in `UnigridsCore` as plain data: `Polyline`,
  `PlaceBoundary`, `MapFilter`, `MapDetail`. The wrapper only draws.

## Consequences

- The map meets §5's behaviour on both platforms with one code path, and the rules that
  decide what shows at which zoom are unit-tested without a map.
- The wrapper is platform code with `#if os(iOS)` branches, which the rest of the app
  avoids. It is contained in `UnigridsFeatures/Map/`.
- Outlines are simplified in the pipeline (Douglas–Peucker, 0.0006° for national parks,
  0.0011° otherwise) to keep the bundle at about half a megabyte; they are for finding a
  place, not for navigation, which the Safety notes already say.
- If a later SwiftUI `Map` gains clustering and tappable overlays, the small maps show the
  way back; the core types would carry over unchanged.
