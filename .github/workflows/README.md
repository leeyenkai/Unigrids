# CI

Four jobs, matching the four things `AGENTS.md` asks a contributor to keep green:

| Job | Runs |
|---|---|
| `package` | `swift test` on `UnigridsKit` — the fast loop |
| `app` | `xcodebuild` for the iOS Simulator and for macOS, because a green package is not proof the app links |
| `lint` | `swiftformat --lint` and `swiftlint --strict` |
| `pipeline` | `ruff` and the pipeline's tests. The bundled reference data is built from a raw snapshot too large to commit, so CI does not rebuild it; `BundledDataTests` in the `package` job check it instead |

## Notes

- **Xcode version.** The jobs select the newest Xcode the runner image carries. The
  project targets iOS 27 / macOS 27, so this needs a runner image with that SDK; until
  GitHub's images ship it, these jobs will fail on the SDK rather than on the code. Pin
  `xcode-select` to a version the image actually has when that happens.
- **Scratch path.** `scripts/test.sh` builds outside the repository to avoid a
  `com.apple.FinderInfo` problem on file-provider-backed checkouts (see
  `scripts/common.sh`). CI checkouts are not synced, so the workflow calls `swift test`
  directly.
