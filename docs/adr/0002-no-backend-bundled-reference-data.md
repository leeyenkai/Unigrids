# 2. No backend; reference data ships inside the app

Date: 2026-10-18

## Status

Accepted

## Context

Unigrids needs a few hundred megabytes of reference data — places, points of interest,
trails, guide text, map tiles — and it needs park maps and trails to work without a
signal, which is exactly when a hiker needs them.

The obvious shape for that is a server: an API in front of a database, with the app
caching what it fetches. The specification (§1, §2, §12) rules it out. This is a free
hobby app with one user at the start; a server would mean hosting, monitoring, a bill,
an auth story and a privacy surface, all for data that changes a few times a year.

## Decision

There is no backend of any kind — no server, no proxy, no hosted cache.

- **Reference data is read-only and bundled in the app.** An offline Python pipeline
  (`Pipeline/`) builds it, and it is replaced wholesale with each App Store release.
- **User data lives in SwiftData**, synced through the user's own private CloudKit
  database. The developer cannot read it.
- **Live calls go straight to their source**: the NPS API for alerts, WeatherKit and
  Open-Meteo for weather, NPS's own servers for brochure PDFs.

## Consequences

Good: nothing to run, nothing to pay for, no user data in the developer's hands, and the
App Store privacy label can honestly read "Data Not Collected". The app works offline by
default rather than as a feature.

Costs, accepted:

- Reference data only changes when the app ships. Anything genuinely live — alerts,
  weather — must come from a public API at runtime.
- The whole bundle must fit the App Store's 4 GB limit. Measuring a real offline pack is
  the pilot milestone's main job.
- The NPS API key is built into the app, so it can be extracted and every user shares one
  rate limit. Acceptable while the app is private; §12 and §17 flag it for revisiting
  before a public release.
- User records must point at reference data by stable ID only, since the rows underneath
  them are replaced. `AGENTS.md` §4 makes that a rule.
