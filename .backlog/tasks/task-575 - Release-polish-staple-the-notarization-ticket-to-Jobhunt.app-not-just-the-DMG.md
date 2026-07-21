---
id: TASK-575
title: >-
  Release polish: staple the notarization ticket to Jobhunt.app (not just the
  DMG)
status: To Do
assignee: []
created_date: '2026-06-20 18:19'
updated_date: '2026-07-21 22:59'
labels:
  - release
  - distribution
  - dmg
dependencies: []
priority: low
ordinal: 31000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Why

`release-dmg.yml` staples the notarization ticket to the **DMG** but not to **Jobhunt.app** inside it.
`spctl` accepts the app today because it can verify notarization online. But when a user copies the
app out of the DMG to /Applications while **offline**, the app carries no stapled ticket, so first
launch can be delayed/blocked until it can reach Apple. Stapling the app too makes first launch robust
offline.

## What
Staple the app **before** packaging it into the DMG: after the Sparkle re-sign + smoke check, run
`xcrun notarytool submit`/`stapler` on the app (or submit a zip of the app, then `stapler staple
Jobhunt.app`), then build the DMG from the stapled app and staple the DMG as well. Apple recommends
stapling both.

## Acceptance
- `xcrun stapler validate Jobhunt.app` (copied out of the DMG) succeeds.
- Offline first launch of the copied app shows no Gatekeeper network dependency.
<!-- SECTION:DESCRIPTION:END -->
