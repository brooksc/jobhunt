---
id: TASK-375
title: 'Store recovery: Do not move the failed store aside before restore succeeds'
status: To Do
assignee: []
created_date: '2026-06-12 22:44'
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
- [ ] #1 StoreRecoveryView stages and validates the selected backup before moving the current failed store aside.
- [ ] #2 If restore fails, the previous store path remains recoverable or is restored automatically.
- [ ] #3 Recovery UI tests or focused unit coverage exercise restore failure after validation.
<!-- AC:END -->
