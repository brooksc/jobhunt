---
id: TASK-566
title: 'Release: complete Sparkle 2 auto-update (currently a manual-download stub)'
status: To Do
assignee: []
created_date: '2026-06-20 04:05'
labels:
  - release
  - distribution
  - dmg
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Why

`app/Platform/SparkleUpdater.swift` is a 17-line **stub**: `checkForUpdates()` just opens
`https://github.com/brooksc/jobhunt/releases/latest` in a browser for a manual download — there is
NO real auto-update. The DMG signing + notarization pipeline (`.github/workflows/release-dmg.yml`,
TASK-401 hardened runtime) and the MAS pipeline (`release-mas.yml`) **are** built; auto-update is the
gap. This was discussed as the deferred release item but was never tracked.

Not a hard blocker for a first DMG release (the manual-download stub is a valid fallback), but it's
the only missing piece of "ship + keep users current," so: high.

## What's missing
- **Sparkle 2 SPM dependency** + an `SPUStandardUpdaterController` wired into the app (DMG build only,
  `#if !MAS_BUILD` — MAS uses the App Store).
- **`SUFeedURL`** (the appcast: `…/releases/latest/download/appcast.xml`) and the **`SUPublicEDKey`**
  (EdDSA public key) in the DMG Info.plist / `Project.swift` — neither is configured today.
- **Appcast generation + EdDSA `sign_update`** of the DMG in `release-dmg.yml`, publishing
  `appcast.xml` as a release asset. The EdDSA private key goes in CI secrets.
- Replace `SparkleUpdater.checkForUpdates()` (browser open) with the real updater; keep a sensible
  "Check for Updates…" menu item.

## Acceptance
- A DMG build checks the appcast, and an available newer signed build installs via Sparkle.
- EdDSA signature is verified (a tampered DMG is rejected).
- MAS build is unaffected (no Sparkle).
- The release workflow publishes a valid `appcast.xml` for each tagged release.

## Note on the rest of the release pipeline
DMG codesign + notarize + staple and the notarization smoke check already exist in
`release-dmg.yml`; MAS in `release-mas.yml`. If those need a readiness pass (signing identity in
secrets, a real end-to-end tag → notarized artifact dry run), track that separately.
<!-- SECTION:DESCRIPTION:END -->
