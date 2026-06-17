---
id: TASK-401
title: >-
  DMG release: Explicitly enable and smoke-check hardened runtime for Developer
  ID notarization
status: Done
assignee: []
created_date: '2026-06-12 23:35'
updated_date: '2026-06-17 05:06'
labels:
  - audit
  - release
  - dmg
  - notarization
  - security
dependencies: []
references:
  - Project.swift
  - .github/workflows/release-dmg.yml
  - config/entitlements/Jobhunt-DMG.entitlements
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The DMG release notarizes the app, but project settings do not explicitly configure hardened runtime and release smoke checks do not assert it. Developer ID apps should explicitly enable hardened runtime and verify it before notarization to avoid late release failures or generated-default ambiguity.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Release-DMG configuration explicitly enables hardened runtime for the app target and bundled helper where required.
- [x] #2 DMG release smoke checks verify the hardened runtime flag before notarization.
- [x] #3 Notarization failure diagnostics are preserved in workflow logs.
- [x] #4 Release documentation records the hardened-runtime expectation for Developer ID builds.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
AC#1: Project.swift sets `ENABLE_HARDENED_RUNTIME = YES` at the project level for Debug-DMG + Release-DMG, cascading to the app target and the bundled `jobhunt-mcp` helper, so signing always emits `--options runtime` instead of relying on a generated default (MAS uses the App Sandbox — hardened runtime is DMG-only). AC#2: release-dmg.yml's smoke check now asserts `codesign -dvv … flags=…(runtime)` on both the app and helper BEFORE notarization, failing with a clear error otherwise. AC#3: the Notarize step captures the submission output and, on failure, fetches `notarytool log <submission-id>` into the workflow logs so the rejection reason is visible in CI. AC#4: CLAUDE.md's new "Release (Developer ID / DMG)" section records the hardened-runtime requirement + the smoke-check/diagnostics behavior. App builds Debug-DMG unsigned (the flag is moot without signing); workflow YAML parses. Can't run a real signed/notarized release here — verified by build + YAML parse + review.
<!-- SECTION:FINAL_SUMMARY:END -->
