# App target

Deliberately thin. This folder holds only what an app bundle needs:

- `UnigridsApp.swift` — the `@main` entry point, which loads the bundled dataset and the
  user's SwiftData store and hands both to `RootTabView`.
- `Assets.xcassets` — app icon and accent colour. **The icon must be an original mark and
  never the NPS arrowhead** (`AGENTS.md` §5); the appiconset is currently empty, which
  Xcode renders as a placeholder.
- `Unigrids.entitlements` — the iCloud and CloudKit entitlement for syncing the log. Not
  wired into the build settings yet; see the note in that file.

Everything else is in `Packages/UnigridsKit` (`docs/adr/0003`).
