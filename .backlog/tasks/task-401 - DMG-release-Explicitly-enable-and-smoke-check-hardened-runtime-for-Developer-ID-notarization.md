---
id: TASK-401
title: >-
  DMG release: Explicitly enable and smoke-check hardened runtime for Developer
  ID notarization
status: To Do
assignee: []
created_date: '2026-06-12 23:35'
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
- [ ] #1 Release-DMG configuration explicitly enables hardened runtime for the app target and bundled helper where required.
- [ ] #2 DMG release smoke checks verify the hardened runtime flag before notarization.
- [ ] #3 Notarization failure diagnostics are preserved in workflow logs.
- [ ] #4 Release documentation records the hardened-runtime expectation for Developer ID builds.
<!-- AC:END -->
