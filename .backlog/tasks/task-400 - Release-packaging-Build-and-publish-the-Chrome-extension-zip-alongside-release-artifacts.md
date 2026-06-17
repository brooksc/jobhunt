---
id: TASK-400
title: >-
  Release packaging: Build and publish the Chrome extension zip alongside
  release artifacts
status: Done
assignee: []
created_date: '2026-06-12 23:35'
updated_date: '2026-06-17 05:08'
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
- [x] #1 A release tag produces a Chrome extension zip for the matching extension manifest version, or release docs explicitly require a separate packaging/upload step.
- [x] #2 The generated extension zip is attached to the GitHub release or uploaded as a workflow artifact as appropriate.
- [x] #3 The package contents are allowlist-verified and exclude tests/dev files.
- [x] #4 Chrome Store listing artifact references are updated during release preparation.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Integrated extension packaging into the DMG release workflow. A new "Package Chrome extension" step runs scripts/package-extension.sh (version-stamped from extension/manifest.json) and checksums the result (AC#1); the "Upload to GitHub Release" step now attaches `chromestore/jobhunt-capture-<version>.zip` + its `.sha256` alongside the DMG (AC#2). AC#3: the script builds from an explicit allowlist via a clean staging dir — verified locally it produces an 18-file zip with no tests/package.json/node_modules. AC#4: store-listing.md (TASK-415/418) references the zip by `<version>` and documents it as generated + non-authoritative-until-regenerated, so references stay valid across releases. Verified package-extension.sh output + workflow YAML parse. Can't run a real tagged release here — verified by local packaging run + YAML parse + review.
<!-- SECTION:FINAL_SUMMARY:END -->
