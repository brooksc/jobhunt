---
id: TASK-424
title: 'Test stores: Fail closed when fixture or UI-test cleanup fails'
status: To Do
assignee: []
created_date: '2026-06-13 04:22'
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
- [ ] #1 UI-test store setup fails with a clear error when the temp directory cannot be created or an old store/sidecar file cannot be removed.
- [ ] #2 Fixture-copy setup fails with a clear error when its destination directory cannot be created or old destination files cannot be removed.
- [ ] #3 Cleanup covers the sidecar naming patterns actually produced by SQLite/SwiftData for the configured store URLs.
- [ ] #4 Existing successful UI-test and fixture launch paths continue to work.
- [ ] #5 Add focused tests or helper-level coverage that simulates cleanup failure or validates cleanup errors are propagated.
<!-- AC:END -->
