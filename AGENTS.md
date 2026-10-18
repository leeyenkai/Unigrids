# AGENTS.md — working agreement

This is the contract for anyone working in this repository, human or coding agent.
Read it before changing anything. `CLAUDE.md` points here; there is one copy of these
rules, not two.

- **What to build** lives in [`SPECIFICATION.md`](SPECIFICATION.md). It is the source of
  truth and it evolves — change it in the same commit as the code that makes it true.
- **What shipped** lives in [`CHANGELOG.md`](CHANGELOG.md).
- **What is in and out of the current milestone** lives in
  [`docs/mvp-scope.md`](docs/mvp-scope.md).
- **Why the architecture is the way it is** lives in [`docs/adr/`](docs/adr/).

## 1. Orientation

Unigrids is a native SwiftUI app for iPhone, iPad and Mac that maps, documents and logs
visits to US public lands. There is **no backend**. Reference data ships inside the app;
user data lives in SwiftData synced through the user's own iCloud.

```
App/                      Thin app target: @main entry point, assets, entitlements
Packages/UnigridsKit/     Almost all code, as a local Swift package
  UnigridsCore            Domain model, value types, pure rules. No UI, no I/O.
  UnigridsReference       Read-only bundled reference data + its loader
  UnigridsLog             SwiftData user store and the services over it
  UnigridsDesign          Unigrid design system and native design tokens
  UnigridsFeatures        SwiftUI screens
Pipeline/                 Offline Python pipeline that builds the bundled data
scripts/                  bootstrap / build / test / lint
```

### Module dependency rule

Dependencies point one way only:

```
UnigridsFeatures  ->  UnigridsDesign, UnigridsLog, UnigridsReference, UnigridsCore
UnigridsLog       ->  UnigridsCore
UnigridsReference ->  UnigridsCore
UnigridsDesign    ->  UnigridsCore
UnigridsCore      ->  (Foundation only)
```

`UnigridsCore` must stay free of SwiftUI, MapKit, SwiftData and networking so its rules
stay fast to test. If you need a new dependency edge, that is an ADR, not a quick fix.

## 2. Commands

```bash
scripts/bootstrap.sh   # check the toolchain, resolve packages
scripts/test.sh        # swift test on UnigridsKit  (the fast loop — use this)
scripts/build.sh       # xcodebuild for iOS Simulator and macOS
scripts/lint.sh        # swiftformat --lint + swiftlint + ruff on the pipeline
```

The fast loop is `cd Packages/UnigridsKit && swift test`. Run `scripts/build.sh` before
you claim an app-level change works — the package compiling is not the same as the app
building for both platforms.

Before handing work back, both of these must pass:

```bash
scripts/test.sh && scripts/build.sh
```

If you cannot get them green, say so plainly and show the failure. Do not describe
unverified work as done.

## 3. Swift conventions

- **Swift 6 language mode, strict concurrency.** Warnings are errors in CI. Model types
  are `Sendable` value types; anything touching UI is `@MainActor`.
- **Value types by default.** Reach for `struct` and `enum`; `final class` only for
  SwiftData models and reference semantics you can justify.
- **Observation, not ObservableObject.** `@Observable` for state that views read.
- **No view models for simple screens.** Views read the store directly (MV, not MVVM);
  extract a type when there is real logic to test. See
  [`docs/adr/0004-mv-over-mvvm.md`](docs/adr/0004-mv-over-mvvm.md).
- **Small subviews.** A `body` longer than roughly 40 lines wants splitting into named
  subviews, not `@ViewBuilder` helpers returning `some View`.
- **Explicit access control.** `public` only where a module boundary genuinely needs it;
  `internal` otherwise. New public API in `UnigridsCore` carries a doc comment.
- **No force unwraps and no `try!`** outside tests. Bundled data loading fails loudly at
  startup in debug and degrades to an empty store in release.
- **Formatting is mechanical.** `swiftformat .` and `swiftlint` decide; configuration is
  in `.swiftformat` and `.swiftlint.yml`. Do not argue with them in review.
- **Comments explain why.** Match the density of the surrounding file. Never narrate what
  the next line does.

### Tests

- Swift Testing (`import Testing`, `@Test`, `#expect`), not XCTest, for new tests.
- Every rule in `UnigridsCore` gets a test: the America 250 date rule, passport region
  assignment, stamp impression determinism, measurement formatting.
- `UnigridsLog` tests use an in-memory `ModelContainer`; they never touch CloudKit.
- Fix the test or fix the code. Never delete or `#expect(true)` a failing assertion to
  get green.

## 4. Data rules

**Reference data is read-only and replaceable.** The pipeline regenerates it wholesale
with each release. Therefore:

- User records reference places, points of interest and trails **only by stable
  `UnigridsID`**. Never store a name, a coordinate or an array index as the link.
- An ID that no longer resolves must degrade gracefully — a visit to a place that left
  the dataset still shows in the log, with an "unknown place" placeholder.
- Reference types are `Codable` and decoded from bundled JSON. Adding a field means a
  default, so old bundles keep decoding during development.

**User data is the user's.** It syncs through the private CloudKit database. Every
CloudKit-backed SwiftData property needs a default value or must be optional, or the
container will not initialise.

The committed seed under
`Packages/UnigridsKit/Sources/UnigridsReference/Resources/reference/` is hand-authored,
not pipeline output. Keep its `README.md` honest: if you add a figure you did not verify,
mark it. **Do not invent park statistics.** An absent value is correct; a plausible
fabricated one is a bug that reaches the user as a fact.

## 5. Hard guardrails

These come from the specification's principles. Breaking one is not a judgement call.

| Never | Why |
|---|---|
| Add a server, proxy, backend or hosted service | "Nothing to run" — the app talks only to Apple services and public APIs (§2, §12) |
| Add an analytics SDK, ads or crash reporting that phones home | The App Store privacy label is "Data Not Collected" (§15) |
| Add accounts, sign-in or a social feed | Privacy-first; sync is the user's own iCloud (§1, §15) |
| Use the NPS arrowhead, in the app or the icon | Registered trademark; needs the NPS Director's written permission (§15) |
| Imply NPS affiliation or endorsement | A non-affiliation line ships in onboarding and About (§14, §15) |
| Commit an API key, certificate or provisioning profile | See "Secrets" below |
| Upload a location track, or store one | Location is for visit detection and the verified stamp tick only (§15) |
| Copy photo originals out of the photo library | Store asset references plus a small thumbnail (§9) |
| Log a visit without the user confirming it | "Nothing is logged without the user confirming it" (§9) |
| Extract photos or art from brochure PDFs for reuse | Some NPS publication content carries third-party rights (§6, §15) |

### Secrets

The NPS API key is **not** in the repository. It is read from the build environment and
surfaced to the app through a generated Info.plist value; `Secrets.xcconfig` is
gitignored. The specification notes (§12) that a key built into a shipped app can be
extracted and shares one rate limit — acceptable while this is private, revisit before
any public release. Never paste a key into source, a test fixture or a commit message.

## 6. Design language

Two visual modes, and they do not mix (§14):

- **Unigrid** — park guides only. Black title band, park name reversed out in white, a
  grid derived from the brochure panel module (1 column on iPhone, 2–3 on iPad, 3–4 on
  Mac), neo-grotesque sans for headings and data, a serif for longer passages.
- **Native** — map, trips, passport, stats and settings use the current Apple design so
  the app feels at home on each device.

Accessibility is not optional: guides reflow with Dynamic Type and the grid **collapses
to fewer columns rather than shrinking text**. Every pin, panel and chart carries a
VoiceOver label. Check contrast in both light and dark.

## 7. Platform targets

iPhone, iPad and Mac on the **latest OS generation only** (currently iOS 27 / macOS 27).
A native Mac app, not Catalyst. Do not add availability fallbacks for older OS versions —
raise the floor instead. Widgets and the watchOS app arrive in v1.0.

## 8. Changelog and specification discipline

- `CHANGELOG.md` follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
  [Semantic Versioning](https://semver.org/). Every user-visible change adds a line under
  `## [Unreleased]` **in the same commit as the change**. Releases move that block under a
  version heading with a date.
- When behaviour diverges from `SPECIFICATION.md`, the specification is wrong until you
  fix it. Update the relevant section, and add to §17 "Open questions" rather than quietly
  deciding something the owner has not.
- Decisions with lasting architectural weight get an ADR in `docs/adr/`, numbered and
  short.

## 9. Commits

- Conventional-commit prefixes: `feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`,
  `data:` (reference data or pipeline output), `spec:` (specification changes).
- Subject in the imperative, under 72 characters. Body explains why.
- One logical change per commit. Reference data regeneration is its own commit — it is
  large and mechanical, and mixing it with code makes both unreviewable.
- Do not commit or push unless the owner asked for it.

## 10. Working style for agents

- Read `SPECIFICATION.md` for the section you are touching before writing code. The
  answers to most "how should this behave?" questions are already there.
- Prefer finishing one slice end to end — model, store, screen, test — over scaffolding
  five screens that do nothing.
- A stub is fine when it is labelled. An empty screen that pretends to work is not: put
  it in `docs/mvp-scope.md` under "Not yet built" and make the UI say so.
- If the specification is silent or contradictory, make the smallest reasonable call,
  write it down in §17, and carry on. Do not block on a question you can answer with a
  documented assumption.
