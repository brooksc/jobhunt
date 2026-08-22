---
id: TASK-681
title: Availability outcome writes can overlap SQLite restore
status: Done
assignee: []
created_date: '2026-08-21 20:26'
updated_date: '2026-08-22 03:37'
labels:
  - bug
  - restore
  - persistence
  - concurrency
dependencies: []
references:
  - TASK-546
  - TASK-554
  - app/Shell/AppServices.swift
  - core/Services/RestoreCoordinator.swift
modified_files:
  - app/Views/Jobs/JobsView.swift
  - app/Views/Settings/SettingsTab.swift
  - app/Shell/AppServices.swift
  - core/Services/RestoreCoordinator.swift
  - tests/CoreTests/RestoreCoordinatorTests.swift
priority: high
type: bug
ordinal: 55000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Data-integrity regression found during the 2026-08-21 code review. Foreground availability checks can outlive runtime shutdown and start an unowned outcome write after shutdown reports quiescence. Restore then manipulates the live SQLite, WAL, and SHM files while that write may still be queued or running, violating the single-writer restore boundary.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Restore quiescence accounts for every in-flight foreground availability check and outcome write
- [ ] #2 No new store write can begin after shutdown enters its closing state
- [ ] #3 Shutdown waits for already accepted foreground store writes before backup or file replacement begins
- [ ] #4 A late availability completion during shutdown cannot write to the old or replacement store
- [ ] #5 Regression coverage delays an availability completion across shutdown and proves restore does not overlap the write
<!-- AC:END -->
