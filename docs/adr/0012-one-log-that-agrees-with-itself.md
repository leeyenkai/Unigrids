# 12. One log that agrees with itself

Date: 2026-10-23

## Status

Accepted

## Context

The passport, the map, the Trips list and Stats all read one log (SPECIFICATION.md §9:
"the passport and the log always agree"). Before the production pass, the log could
disagree with itself in four ways:

- **Two visits for one day.** A check-in made a second visit beside a stamp's visit on
  the same day.
- **Orphan stamps.** Deleting a visit left its stamps behind. The passport said "been"
  while the map said "not been". A code comment called this deliberate.
- **The wrong day.** Days came from `Calendar.current`, in the device's time zone and
  calendar. An evening in Hawaiʻi could land on the next day. On a phone set to the
  Buddhist calendar, the America 250 seal never applied.
- **Saves that half-happened.** A failed save left its inserts in the context, to be
  written by the next save.

## Decision

**Days are the place's.** `UnigridsCalendar` is Gregorian, with a fixed locale and an
explicit time zone: the place's own, else its state's main zone, else the device's. A day
picked with a date-only picker is stored at noon in that zone.

**One visit per place per day.** Check-ins, stamps, hikes and photo imports join that
day's visit at the place, or start it. A hike-made visit says it was a hike.

**Records go together:**
- Deleting a visit takes its stamps, hikes, check-ins and weather. The confirmation says
  what goes with it.
- Deleting the only stamp on a visit that stamping made, and that holds nothing else,
  takes that visit too.
- Moving a visit to another day moves everything on it, and drops weather recorded for
  the old day. A day that already has a visit to the place keeps that visit: what was
  on the moved one joins it, and their notes are kept together.
- Importing a backup merges by record, and a visit for a place and day the log already
  has joins the visit there instead of adding a second.

**Trips are matched conservatively** (`TripMatching`). An unlinked log entry joins a dated
trip that lists the place and covers the day. Failing that, while logging live, it joins
the one undated trip under way.

**Every change can be taken back.** A deletion returns an `UndoableChange` holding an
archive of what it removed; undoing it merges that archive back under the original record
identifiers. Making something — a stamp, a hike, an import — returns the identifiers it
made, and undoing it removes them.

**Saves are atomic.** A failed save rolls back.

**Export is complete.** `LogArchive` holds every model and every field. A test fails if a
stored attribute is left out, and an export imports back by merging on record identifier.

## Consequences

- Deleting a visit can delete stamps, which the old comment refused to do. The
  confirmation and the undo make that safe, and the passport and map can't disagree.
- Rules that used to live in views are now in `LogStore`, `Deletion` and Core, with tests.
