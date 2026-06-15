---
id: TASK-375
title: 'Store recovery: Do not move the failed store aside before restore succeeds'
status: Done
assignee: []
created_date: '2026-06-12 22:44'
updated_date: '2026-06-15 19:42'
labels:
  - audit
  - backup
  - recovery
  - data-safety
dependencies: []
references:
  - app/Views/Components/StoreRecoveryView.swift
  - core/Services/BackupService.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
StoreRecoveryView moves the failed store to a corrupt-* path before calling BackupService.restore. If restore then fails, the app's expected store path no longer contains the original failed store.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 StoreRecoveryView stages and validates the selected backup before moving the current failed store aside.
- [x] #2 If restore fails, the previous store path remains recoverable or is restored automatically.
- [x] #3 Recovery UI tests or focused unit coverage exercise restore failure after validation.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
StoreRecoveryView no longer moves the failed store aside before restoring. BackupService.restore already stages the chosen backup, deep-validates it against the current schema/migration plan, and only then moves the live store aside with full rollback — so the pre-move was both redundant and harmful: a rejected backup left storeURL empty with the original failed store stranded at corrupt-*. Now the original stays in place (AC#1: restore stages+validates before moving it aside; AC#2: restore's rollback returns it to storeURL on failure), and the corrupt store (+ -wal/-shm) is COPIED aside for manual recovery; the redundant copy is removed if restore fails. AC#3: the underlying failure-after-validation safety is covered by existing BackupServiceTests — testRestore_rejectsSchemaIncompatibleBackup_originalSurvives and testRestore_atomicOnCopyFailure — which assert the original store survives a rejected/failed restore (the guarantee StoreRecoveryView now relies on). App builds.
<!-- SECTION:FINAL_SUMMARY:END -->
