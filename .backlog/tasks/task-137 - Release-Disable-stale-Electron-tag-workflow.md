---
id: TASK-137
title: 'Release: Disable stale Electron tag workflow'
status: Done
assignee: []
created_date: '2026-06-11 03:39'
updated_date: '2026-06-11 19:00'
labels:
  - release
  - ci
  - cutover
  - electron-cleanup
dependencies: []
references:
  - .github/workflows/release.yml
  - .github/workflows/release-dmg.yml
  - .github/workflows/release-mas.yml
  - >-
    .backlog/tasks/task-064 -
    Cutover-cleanup-remove-Electron-Node-React-update-docs.md
modified_files:
  - .github/workflows/release.yml
  - .github/workflows/release-dmg.yml
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The repository still contains `.github/workflows/release.yml` triggered on `v*` tags that runs npm/electron build commands, but the current Swift/Tuist tree has no package.json. This conflicts with the Swift release workflows and can fail releases on every tag.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Electron-era `.github/workflows/release.yml` is removed, disabled, or renamed so it no longer runs on `v*` tags.
- [ ] #2 A tag dry-run or workflow inspection confirms only the intended Swift DMG/MAS release workflows trigger for release tags.
- [ ] #3 Any useful secrets documentation from the stale workflow is moved to the current Swift release docs before deletion.
- [ ] #4 Cutover cleanup task references are updated if this workflow was part of the planned Electron removal.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Deleted .github/workflows/release.yml (the stale Electron/npm workflow that ran on v* tags). Moved its secrets documentation comment block into release-dmg.yml so no information is lost. Only release-dmg.yml, release-mas.yml, and swift-build.yml now exist — all are Swift/Tuist workflows.
<!-- SECTION:FINAL_SUMMARY:END -->
