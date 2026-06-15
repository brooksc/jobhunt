---
id: TASK-374
title: 'Backup restore: Make live store replacement atomic with rollback on failure'
status: Done
assignee: []
created_date: '2026-06-12 22:44'
updated_date: '2026-06-15 04:09'
labels:
  - audit
  - backup
  - restore
  - data-safety
dependencies: []
references:
  - core/Services/BackupService.swift
  - tests/CoreTests/BackupServiceTests.swift
modified_files:
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
- [x] #1 Restore uses an atomic replace or move-old-aside strategy that can roll back if replacement fails.
- [x] #2 WAL/SHM companion cleanup remains correct and does not lose the original store on mid-restore failures.
- [x] #3 Tests simulate failure after staging and verify the original store remains recoverable.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Rewrote BackupService.restore to a move-aside + rollback strategy. The live store and its -wal/-shm companions are moved aside (not deleted); the staged backup is moved into place; only on full success are the set-aside originals discarded. Any failure rolls the originals back, so a mid-restore error can never leave the user without a store. WAL/SHM cleanup is preserved (the restored VACUUM-INTO file is self-contained → clean checkpoint). New test testRestore_rejectsSchemaIncompatibleBackup_originalSurvives simulates failure after staging and asserts the original store remains intact and readable; testRestore_replacesDataAndStoreIsReadable verifies the happy path and that no .incoming/.old leftovers remain. All 11 BackupServiceTests pass.
<!-- SECTION:FINAL_SUMMARY:END -->
