# CI

Four jobs, matching the four things `AGENTS.md` asks a contributor to keep green:

| Job | Runs |
|---|---|
| `package` | `swift test` on `UnigridsKit` — the fast loop |
| `app` | `xcodebuild` for the iOS Simulator and for macOS, because a green package is not proof the app links |
| `lint` | `swiftformat --lint` and `swiftlint --strict` |
| `pipeline` | `ruff` and the pipeline's tests. The bundled reference data is built from a raw snapshot too large to commit, so CI does not rebuild it; `BundledDataTests` in the `package` job check it instead |

## Notes

- **Xcode version.** The project targets iOS 27 / macOS 27, so the `package` and `app`
  jobs run on GitHub's `xcode-27` image and select `/Applications/Xcode_27.app`. The
  image was a public preview when this was set up (October 2026), so expect the
  occasional queue; move to the general macOS 27 image once it carries Xcode 27. The
  `lint` and `pipeline` jobs need no Xcode and stay on their own images. On a private
  repository, macOS minutes count against the Actions allowance at a higher rate than
  Linux minutes.
- **Scratch path.** `scripts/test.sh` builds outside the repository to avoid a
  `com.apple.FinderInfo` problem on file-provider-backed checkouts (see
  `scripts/common.sh`). CI checkouts are not synced, so the workflow calls `swift test`
  directly.
