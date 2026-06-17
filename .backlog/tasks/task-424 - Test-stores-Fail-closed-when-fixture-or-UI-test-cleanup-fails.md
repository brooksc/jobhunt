---
id: TASK-424
title: 'Test stores: Fail closed when fixture or UI-test cleanup fails'
status: Done
assignee: []
created_date: '2026-06-13 04:22'
updated_date: '2026-06-17 04:50'
labels:
  - audit
  - fixtures
  - tests
dependencies: []
references:
  - app/JobhuntApp.swift
  - core/Models/ModelContainerFactory.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
UI-test and fixture temp-store cleanup currently uses `try?` for directory creation and store/WAL/SHM deletion. If deletion fails because of permissions, locks, or stale sidecar files, the app can continue and open old data instead of failing the test setup. Isolation failures should be explicit because stale test data can mask regressions.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 UI-test store setup fails with a clear error when the temp directory cannot be created or an old store/sidecar file cannot be removed.
- [x] #2 Fixture-copy setup fails with a clear error when its destination directory cannot be created or old destination files cannot be removed.
- [x] #3 Cleanup covers the sidecar naming patterns actually produced by SQLite/SwiftData for the configured store URLs.
- [x] #4 Existing successful UI-test and fixture launch paths continue to work.
- [x] #5 Add focused tests or helper-level coverage that simulates cleanup failure or validates cleanup errors are propagated.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added `ModelContainerFactory.freshTestStore(at:)` — creates the parent dir and removes the existing store + sidecars, THROWING if cleanup can't complete, so a UI-test run can never silently open stale data (AC#1). `JobhuntApp .uiTest` now uses it (was `try?` + recreating the container over old data); `.fixtureGenerate` uses `try` (not `try?`) for its output directory (AC#2 — and `fixture(copying:)` was already fail-closed with a per-call UUID dir from TASK-420). AC#3: fixed the sidecar names — cleanup now targets CoreData/SQLite's hyphen-suffixed `…store-wal`/`…store-shm` (centralized in `storeAndSidecars(of:)`), not the previously-wrong `.wal`/`.shm` extensions that never matched real sidecars. AC#4: the success paths still open normally. AC#5: FreshTestStoreTests cover the hyphen sidecar names, no-carryover-of-previous-run-data, fail-closed when the directory can't be created, and clean-slate success. 822 CoreTests green; app builds.
<!-- SECTION:FINAL_SUMMARY:END -->
