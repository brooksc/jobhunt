---
id: TASK-331
title: >-
  Backup validation: Verify Jobhunt-compatible schema, not only SQLite magic
  header
status: Done
assignee: []
created_date: '2026-06-12 20:06'
updated_date: '2026-06-12 20:58'
labels:
  - audit
  - backup
  - restore
  - validation
  - data-integrity
dependencies: []
references:
  - core/Services/BackupService.swift
  - app/Views/Settings/SettingsTab.swift
  - app/Views/Components/StoreRecoveryView.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
BackupService.isValidSQLite only checks the SQLite file header. Arbitrary SQLite files can pass selection and restore validation even if they are not compatible Jobhunt/SwiftData stores, leading to failed relaunches or unusable data.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Backup validation proves the file is a compatible Jobhunt store, not merely any SQLite database.
- [ ] #2 Settings and recovery restore paths use the stronger validation before replacing local data.
- [ ] #3 Tests cover arbitrary SQLite files, valid backups, and corrupted/truncated backups.
<!-- AC:END -->
