---
id: TASK-397
title: >-
  Release versioning: Reconcile Project.swift, extension manifest, and Chrome
  Store listing versions
status: Done
assignee: []
created_date: '2026-06-12 23:34'
updated_date: '2026-06-15 06:02'
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
modified_files:
  - Project.swift
  - chromestore/store-listing.md
  - scripts/bump-version.sh
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Current checked-in versions disagree: Project.swift is 1.0.0, extension/manifest.json is 1.0.1, and Chrome Store listing/artifact references still say 0.2.2. Align the source versions and store submission metadata so CI, release tags, and Chrome upload artifacts agree.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Project.swift marketingVersion and extension/manifest.json version match.
- [x] #2 Chrome Store listing metadata and extension zip filename reference the current extension version.
- [x] #3 Version parity workflow passes on the reconciled files.
- [x] #4 Release documentation explains which files are updated by `scripts/bump-version.sh` and which submission metadata must be manually refreshed.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Aligned all three to 1.0.1 (user-chosen; the higher value, safe for Chrome Web Store version monotonicity). Bumped Project.swift marketingVersion 1.0.0→1.0.1 via bump-version.sh (manifest.json was already 1.0.1, so AC#1 satisfied). Updated chromestore/store-listing.md Version row 0.2.2→1.0.1 and the Extension-zip reference to jobhunt-capture-1.0.1.zip noted as built-at-release (AC#2). Verified version-parity locally: App=1.0.1 == Ext=1.0.1 (AC#3). Documented in the bump-version.sh header exactly which files it updates (Project.swift marketingVersion + currentProjectVersion, extension manifest version) and which must be manually refreshed at release (store-listing Version + zip filename) (AC#4). Regenerated the Xcode project to reflect the new version.
<!-- SECTION:FINAL_SUMMARY:END -->
