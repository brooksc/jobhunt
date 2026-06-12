---
id: TASK-397
title: >-
  Release versioning: Reconcile Project.swift, extension manifest, and Chrome
  Store listing versions
status: To Do
assignee: []
created_date: '2026-06-12 23:34'
labels:
  - audit
  - release
  - versioning
  - chrome-extension
dependencies: []
references:
  - Project.swift
  - extension/manifest.json
  - chromestore/store-listing.md
  - scripts/bump-version.sh
  - .github/workflows/version-parity.yml
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Current checked-in versions disagree: Project.swift is 1.0.0, extension/manifest.json is 1.0.1, and Chrome Store listing/artifact references still say 0.2.2. Align the source versions and store submission metadata so CI, release tags, and Chrome upload artifacts agree.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Project.swift marketingVersion and extension/manifest.json version match.
- [ ] #2 Chrome Store listing metadata and extension zip filename reference the current extension version.
- [ ] #3 Version parity workflow passes on the reconciled files.
- [ ] #4 Release documentation explains which files are updated by `scripts/bump-version.sh` and which submission metadata must be manually refreshed.
<!-- AC:END -->
