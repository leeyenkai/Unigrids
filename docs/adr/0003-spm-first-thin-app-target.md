# 3. Put the code in a Swift package, keep the app target thin

Date: 2026-10-18

## Status

Accepted

## Context

The default Xcode shape for an app like this is one target holding every source file.
That works, but it has two costs here. The feedback loop runs through `xcodebuild` and a
simulator even for a pure date-arithmetic change, and nothing enforces a boundary between
the domain rules and the UI — so the rules end up reachable only by booting the app.

A coding agent working in this repo pays both costs repeatedly.

## Decision

Almost all code lives in a local Swift package, `Packages/UnigridsKit`, with five modules:

| Module | Holds | May import |
|---|---|---|
| `UnigridsCore` | Domain model, value types, pure rules | Foundation only |
| `UnigridsReference` | Read-only bundled data and its loader | Core |
| `UnigridsLog` | SwiftData user store and services | Core |
| `UnigridsDesign` | Unigrid design system, native tokens | Core |
| `UnigridsFeatures` | SwiftUI screens | all of the above |

`App/Unigrids.xcodeproj` contains only what an app bundle needs: the `@main` entry point,
assets, entitlements and the Info.plist settings. It depends on the package by path.

`UnigridsCore` importing nothing but Foundation is the load-bearing part. It is what makes
the America 250 rule, passport region assignment and stamp impression determinism testable
in milliseconds.

## Consequences

`swift test` runs the whole suite in seconds without Xcode's build system, and the module
graph documents itself — a feature cannot reach into the domain's internals, and the
domain cannot accidentally depend on SwiftUI.

Costs: the Xcode project is hand-maintained rather than generated, and SwiftUI previews
in package modules need a host app for anything that touches bundled resources. Both are
small against the loop time. `scripts/build.sh` still builds the real app for both
platforms, because a green package is not proof the app links.
