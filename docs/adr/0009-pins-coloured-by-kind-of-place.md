# 9. Pins are coloured by kind of place, not by agency

Date: 2026-10-20

## Status

Accepted. Amends [ADR 0007](0007-one-identity-across-every-screen.md), which made a
place's agency its ink.

## Context

ADR 0007 gave every place marker two cues: its tier as a shape and its agency as an
ink. When the map grew to 2,052 places in eighteen site types, a pictogram inside the
marker became the third cue. In use that system failed on the map itself:

- **The pins looked alike.** The National Park Service's two inks, the Forest Service's
  and the BLM's were all dark greens and browns, and every unvisited pin was a hollow
  outline in that ink on white. A battlefield and a seashore differed only by a glyph
  eleven points tall.
- **Hollow pins were weak.** A thin outline and a small glyph in a dark ink carry little
  contrast on map tiles, least of all on the dark map that is the app's default.
- **The diamond had no room.** Only the middle square of a diamond holds a glyph, and a
  diamond reads as a road warning sign.
- **National parks read as photos.** White mountains in a white-framed black square is
  the shape of a photo placeholder.

What a reader scanning the map wants first is *what kind of place* something is. Who runs
it matters less, and mostly follows from the kind: forests are the Forest Service's,
refuges Fish and Wildlife's, conservation areas the BLM's.

## Decision

- **Colour is the kind of place.** `SiteInk` in `UnigridsCore` holds eleven colours, one
  per family of site types: national parks black, monuments crimson, history (historic
  sites, battlefields, memorials) brown, water (seashores, recreation areas, rivers)
  blue, wild land (forests, grasslands, preserves) green, refuges teal, BLM conservation
  areas amber, natural landmarks magenta, state parks violet, roads (parkways, byways)
  orange and other NPS sites grey. Outlines and routes use the same colours.
- **Pins are solid**: the colour filled, a white pictogram, a white keyline and a soft
  shadow, so every pin holds on any base map. Visited is a green tick at the corner;
  planned is a dashed ring. Hollow-versus-filled survives only in the small plain markers
  in lists, where there is no pictogram.
- **Shape stays the tier**, as the second cue for anyone who cannot tell two colours
  apart: square for the NPS (a large black one for national parks), circle for state
  parks, and a hexagon in place of the diamond for other public land.
- **National parks wear a white star**, not mountains.
- At country scale national parks gather into their own counted cluster, a starred
  black square, rather than piling up; other sites keep their round black clusters.

Tests hold the rules: a white pictogram clears 3:1 on every pin; each colour's scheme
variant clears 3:1 on the surfaces it lands on and keeps its hue; no two pin colours sit
closer than 30 ΔE (CIE76); every site type has a colour and a distinct pictogram.

## Consequences

- The key explains colour, shape and marks in one place, and its chip on the map is a
  strip of swatches rather than four pins that collided.
- `AgencyInk` stays for the one place an agency's colour is still the point, the national
  park grid in Stats, and could carry a manager row later. It no longer colours pins or
  outlines.
- Over satellite imagery the map and the 3D explorer use each colour's dark-scheme
  variant, since the light one (black for national parks) vanishes into terrain.
