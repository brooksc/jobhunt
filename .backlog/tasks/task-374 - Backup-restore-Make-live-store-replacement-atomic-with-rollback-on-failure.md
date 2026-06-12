---
id: TASK-374
title: 'Backup restore: Make live store replacement atomic with rollback on failure'
status: To Do
assignee: []
created_date: '2026-06-12 22:44'
labels:
  - audit
  - backup
  - restore
  - data-safety
dependencies: []
references:
  - core/Services/BackupService.swift
  - tests/CoreTests/BackupServiceTests.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
BackupService.restore copies the backup to .incoming, removes WAL/SHM, deletes the old store, then moves incoming into place. If the final move fails, the original store has already been removed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Restore uses an atomic replace or move-old-aside strategy that can roll back if replacement fails.
- [ ] #2 WAL/SHM companion cleanup remains correct and does not lose the original store on mid-restore failures.
- [ ] #3 Tests simulate failure after staging and verify the original store remains recoverable.
<!-- AC:END -->
