---
id: TASK-327
title: 'Backup restore: Remove real SQLite WAL/SHM companion files'
status: To Do
assignee: []
created_date: '2026-06-12 20:05'
labels:
  - audit
  - backup
  - restore
  - data-integrity
dependencies: []
references:
  - core/Services/BackupService.swift
  - app/Views/Components/StoreRecoveryView.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
BackupService.restore and StoreRecoveryView.startFresh attempt to remove SQLite companion files with appendingPathExtension("wal"/"shm"), which targets jobhunt.store.wal and jobhunt.store.shm. SQLite creates hyphen companions such as jobhunt.store-wal and jobhunt.store-shm, so stale or corrupt companions can survive restore/start-fresh flows and be reused by SwiftData.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Backup restore removes existing <store>-wal and <store>-shm companions before replacing the main store.
- [ ] #2 Store recovery start-fresh and restore flows also move or remove real hyphen companion files.
- [ ] #3 Tests cover existing -wal and -shm files and prove they are not left beside the restored/fresh store.
<!-- AC:END -->
