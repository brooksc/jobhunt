---
id: TASK-400
title: >-
  Release packaging: Build and publish the Chrome extension zip alongside
  release artifacts
status: To Do
assignee: []
created_date: '2026-06-12 23:35'
labels:
  - audit
  - release
  - chrome-extension
  - packaging
dependencies: []
references:
  - .github/workflows/release-dmg.yml
  - scripts/package-extension.sh
  - chromestore/store-listing.md
  - extension/manifest.json
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Release workflows validate extension version parity, but the DMG release uploads only the Mac DMG, checksum, and provenance. The extension packaging script exists separately and current Chrome Store metadata points to stale zips. Integrate extension packaging into the release process or document a separate required release lane.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A release tag produces a Chrome extension zip for the matching extension manifest version, or release docs explicitly require a separate packaging/upload step.
- [ ] #2 The generated extension zip is attached to the GitHub release or uploaded as a workflow artifact as appropriate.
- [ ] #3 The package contents are allowlist-verified and exclude tests/dev files.
- [ ] #4 Chrome Store listing artifact references are updated during release preparation.
<!-- AC:END -->
