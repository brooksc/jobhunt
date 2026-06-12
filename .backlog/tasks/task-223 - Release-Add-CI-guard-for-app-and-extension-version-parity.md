---
id: TASK-223
title: 'Release: Add CI guard for app and extension version parity'
status: To Do
assignee: []
created_date: '2026-06-12 01:32'
labels:
  - release
  - ci
  - extension
dependencies: []
references:
  - Project.swift
  - extension/manifest.json
  - scripts/bump-version.sh
  - .github/workflows/release-dmg.yml
  - README.md
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Project.swift currently has a different app marketing version than extension/manifest.json. Add a release/CI check so the app version and Chrome extension version cannot drift when creating tag releases.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 CI fails when Project.swift marketingVersion and extension/manifest.json version differ.
- [ ] #2 The version parity check runs in the normal build workflow and/or release workflow before packaging artifacts.
- [ ] #3 The release docs explain the single source of truth and version bump procedure.
- [ ] #4 Existing version bump script updates all checked version fields consistently.
<!-- AC:END -->
