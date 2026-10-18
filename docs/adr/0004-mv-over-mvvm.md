# 4. Views read the stores directly (MV, not MVVM)

Date: 2026-10-18

## Status

Accepted

## Context

A SwiftUI app of this shape invites a view model per screen. In practice most of those
view models would be pass-through: a published copy of data that SwiftData and
`@Observable` already deliver to the view, plus the forwarding needed to keep the copy in
step. That is a second source of truth and a class of bug that does not otherwise exist.

The screens that *do* have logic — the panel grid's column count, stats aggregation, the
stamp sheet's date rules — have logic that belongs in `UnigridsCore` or `UnigridsLog`,
where it is testable without a view at all.

## Decision

Views read the stores directly. `@Query` and `@Observable` stores are the state; there is
no view model layer by default.

- Pure derivations (completion counts, region grouping, measurement formatting) are
  functions or value types in `UnigridsCore`, tested directly.
- Anything that mutates user data goes through a service on `UnigridsLog`, not through
  ad-hoc `modelContext` calls scattered in view bodies.
- A screen with genuinely stateful behaviour that is not just its own view state may get
  an `@Observable` model — but as the exception, with the reason in the commit.

## Consequences

Less code and one source of truth, at the cost of giving up the reflex that "every screen
has a view model". The discipline that replaces it: if a view body is hard to read, split
it into subviews; if logic is hard to test, move it down into Core or Log rather than
sideways into a view model.
