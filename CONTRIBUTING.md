# Contributing

Thanks for taking an interest. Unigrids is a small hobby project, so issues and pull
requests are read by one person: a focused change with a clear reason lands fastest.

## Before you start

Read [`AGENTS.md`](AGENTS.md). It is the working agreement for humans and coding agents
alike: the module layout, the Swift conventions, the data rules and the guardrails a
change must not break. The short version of the guardrails:

- No backend, server or hosted service. No analytics, ads, accounts or social feed.
- `UnigridsCore` imports Foundation and nothing else.
- Never invent a park fact. An absent figure is correct; a plausible wrong one ships to
  users as truth.
- Never use the NPS arrowhead or imply NPS endorsement.
- Never commit an API key, certificate or provisioning profile.

For anything larger than a fix, open an issue first so we can agree on the shape before
you write it. Behaviour is specified in [`SPECIFICATION.md`](SPECIFICATION.md); if your
change makes the app behave differently, update the relevant section in the same pull
request.

## Making a change

```bash
scripts/bootstrap.sh                 # check the toolchain, resolve packages
scripts/test.sh                      # the fast loop
scripts/lint.sh                      # SwiftFormat, strict SwiftLint, ruff
scripts/build.sh                     # the app, for the iOS Simulator and macOS
```

A pull request is ready when:

- `scripts/test.sh && scripts/build.sh` pass, and `scripts/lint.sh` is clean.
- New rules in `UnigridsCore` have tests (Swift Testing, not XCTest).
- A user-visible change adds a line under `## [Unreleased]` in
  [`CHANGELOG.md`](CHANGELOG.md).
- Commits use conventional prefixes (`feat:`, `fix:`, `docs:`, `refactor:`, `test:`,
  `chore:`, `data:`, `spec:`), one logical change each.

Reference data under `Packages/UnigridsKit/Sources/UnigridsReference/Resources/reference/`
is built by the pipeline in [`Pipeline/`](Pipeline/). To correct a fact, change the
content file or the source and rebuild; hand edits there are overwritten.

## Licence

By contributing you agree that your contribution is licensed under the
[MIT licence](LICENSE) that covers the rest of the code.
