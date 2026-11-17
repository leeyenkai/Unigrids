# App target

Deliberately thin. This folder holds only what an app bundle needs:

- `UnigridsApp.swift` — the `@main` entry point, which loads the bundled dataset and the
  user's SwiftData store and hands both to `RootTabView`.
- `Assets.xcassets` — the app icon, eleven alternate icons and the accent colour. **Every
  icon is an original mark: never the NPS arrowhead, Japan's national park mark or the
  Norges nasjonalparker logo** (`AGENTS.md` §5).
- `Unigrids.entitlements` — the Mac build's location and Photos entitlements, which the
  hardened runtime needs and which need no development team.
- `Unigrids-iCloud.entitlements` — the iCloud and CloudKit entitlement for syncing the
  log. Not wired into the build: it needs a development team (see the note in that file).
- `PrivacyInfo.xcprivacy` — the privacy manifest.
- `Secrets.plist` — the NPS API key for live US alerts. Gitignored and never committed;
  without it the US alerts are off and everything else works.

Everything else is in `Packages/UnigridsKit` (`docs/adr/0003`).
