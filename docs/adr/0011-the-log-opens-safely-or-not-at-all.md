# 11. The log opens safely or not at all, in a file of its own

Date: 2026-10-23

## Status

Accepted

## Context

The log is the only data Unigrids cannot rebuild. Two things put it at risk.

**A silent in-memory fallback.** If the SwiftData store failed to open, the app fell back
to an in-memory store and carried on. The log looked empty, and everything logged that
session was gone at quit. It didn't take a corrupt file: iOS protects the store until the
device's first unlock, and arrival detection relaunches the app in the background before
then.

**A shared path on the Mac.** The Mac app is unsandboxed while it is unsigned. SwiftData's
default store there is `~/Library/Application Support/default.store`, a single file any
unsandboxed SwiftData app on the machine would also use.

## Decision

**`StoreLoader` opens the log.**
- It opens when the first window appears, not at launch.
- If protected data isn't available yet, it waits for it.
- It retries a failure once, then stops on a screen that gives the error, says the data
  is still on disk, and offers Retry.
- There is no in-memory fallback, except for debug sample-data runs.
- `LogGate` shows that state in every scene, the Mac's Settings window included.

**The log has its own file**: `Application Support/Unigrids/Unigrids.store`, on both
platforms.
- A log already at the default path is moved once: copied, checked to be this app's by
  its tables (`ZVISIT`, `ZSTAMP`, `ZTRIPSTOP`), then removed.
- The check opens the copy read-only, and falls back to `immutable=1` when there is no
  `-shm` to read through.
- A store that isn't this app's is left alone.

**Model changes stay additive.** Every new attribute is optional or defaulted, and enums
are stored as raw strings, so lightweight migration covers them. A store written by the
schema as it stood before the production pass is committed as a test fixture
(`Tests/UnigridsLogTests/Fixtures`), and it must open under the current schema.

**Arrivals before the first unlock wait in memory.** Arrivals noticed then are held there
and merged into the saved list once the list can be read. They never overwrite it.

## Consequences

- A launch that can't open the log is visible and recoverable, instead of quietly losing
  data.
- A model change that would break migration fails a test before it ships.
- Without the fixture test, a `VersionedSchema` would be the next step. It isn't needed
  while changes stay additive.
