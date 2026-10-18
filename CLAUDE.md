# CLAUDE.md

The working agreement for this repository is **[`AGENTS.md`](AGENTS.md)**. Read it before
making changes — it is the single copy of the conventions, commands and guardrails, and
it applies to Claude Code exactly as it applies to a human contributor.

Quick orientation:

| Question | File |
|---|---|
| How do I work in this repo? | [`AGENTS.md`](AGENTS.md) |
| What is this app meant to be? | [`SPECIFICATION.md`](SPECIFICATION.md) |
| What is in the current milestone? | [`docs/mvp-scope.md`](docs/mvp-scope.md) |
| Why is it built this way? | [`docs/adr/`](docs/adr/) |
| What shipped? | [`CHANGELOG.md`](CHANGELOG.md) |

The fast feedback loop:

```bash
cd Packages/UnigridsKit && swift test     # seconds
scripts/build.sh                          # before claiming an app change works
```

Three things that are easy to get wrong here, spelled out in `AGENTS.md`:

1. **No backend, no analytics, no accounts.** Not a preference — a product constraint.
2. **`UnigridsCore` imports Foundation and nothing else.** No SwiftUI, MapKit or SwiftData.
3. **Never invent park facts.** An absent figure is correct; a plausible wrong one ships
   to the user as truth.
