---
id: TASK-373
title: >-
  Backup restore: Validate backups by opening a staged copy with the current
  migration plan
status: To Do
assignee: []
created_date: '2026-06-12 22:44'
labels:
  - audit
  - backup
  - restore
  - data-safety
  - migration
dependencies: []
references:
  - core/Services/BackupService.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
BackupService.isValidSQLite only checks SQLite magic plus expected table names. A backup from an incompatible or future schema can pass validation, replace the live store, and then fail when the app relaunches.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Restore validation opens a staged copy using the current Schema and JobhuntMigrationPlan before touching the live store.
- [ ] #2 Incompatible/future/corrupt Jobhunt-looking SQLite files are rejected with a user-actionable error.
- [ ] #3 Tests cover arbitrary SQLite, valid backup, and schema-incompatible backup cases.
<!-- AC:END -->
