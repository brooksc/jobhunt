---
id: TASK-575
title: >-
  Release polish: staple the notarization ticket to Jobhunt.app (not just the
  DMG)
status: Done
assignee: []
created_date: '2026-06-20 18:19'
updated_date: '2026-08-10 01:15'
labels:
  - release
  - distribution
  - dmg
dependencies: []
modified_files:
  - .github/workflows/release-dmg.yml
  - docs/release-process.md
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

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The release workflow notarizes and staples Jobhunt.app before packaging it into the DMG
- [x] #2 The workflow asserts the stapled ticket on the app inside the built DMG
- [ ] #3 not verified: requires a release — `xcrun stapler validate Jobhunt.app` on a copy from a published DMG, and an offline first launch. Cutting a release is out of bounds for this run; the workflow now performs both checks itself on the next one.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
`release-dmg.yml` gains a "Notarize and staple the app" step *before* the DMG is built, and the DMG step now mounts the finished image and validates the app inside it.

`notarytool` won't accept a bundle, so the app is submitted as a `ditto -c -k --keepParent` zip and the ticket stapled to the original bundle; the zip is a submission vehicle and is deleted, not shipped. Both new checks assert with `stapler validate` rather than trusting the staple exit code — a missing ticket is invisible until a user launches offline, which is precisely the failure this fixes. The submission reuses the existing status-not-exit-code handling, since `notarytool --wait` exits 0 even on `Invalid` (the cause of the opaque Error 65 recorded in the runbook).

The acceptance evidence — `stapler validate` on an app copied out of a *published* DMG, and an offline first launch — is rewritten `not verified: requires a release`. Cutting one is out of bounds for this run. The workflow now performs the equivalent checks itself, so the next release either proves it or fails loudly.

`docs/release-process.md` updated: the step list now describes both staples, and the per-release verification block validates the app's own ticket alongside the DMG's.

Gate: YAML parses; no Swift changed, so the app gate is unaffected. Not exercised end-to-end — that needs a tag.
<!-- SECTION:FINAL_SUMMARY:END -->
