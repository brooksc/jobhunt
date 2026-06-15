---
id: TASK-373
title: >-
  Backup restore: Validate backups by opening a staged copy with the current
  migration plan
status: Done
assignee: []
created_date: '2026-06-12 22:44'
updated_date: '2026-06-15 04:09'
labels:
  - audit
  - backup
  - restore
  - data-safety
  - migration
dependencies: []
references:
  - core/Services/BackupService.swift
modified_files:
  - core/Services/BackupService.swift
  - tests/CoreTests/BackupServiceTests.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
BackupService.isValidSQLite only checks SQLite magic plus expected table names. A backup from an incompatible or future schema can pass validation, replace the live store, and then fail when the app relaunches.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Restore validation opens a staged copy using the current Schema and JobhuntMigrationPlan before touching the live store.
- [x] #2 Incompatible/future/corrupt Jobhunt-looking SQLite files are rejected with a user-actionable error.
- [x] #3 Tests cover arbitrary SQLite, valid backup, and schema-incompatible backup cases.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Restore now validates the staged backup before touching the live store: validateOpensWithMigrationPlan copies the staged .incoming to a throwaway probe and opens it with Schema(SchemaV1.models) + JobhuntMigrationPlan. An incompatible/future/corrupt Jobhunt-looking SQLite (passes the cheap magic+table check but isn't a loadable CoreData store) is rejected with a new user-actionable BackupError.incompatibleStore ("This backup isn't compatible with this version of Jobhunt…") before the swap. Probing on a throwaway copy keeps the staged file pristine. Test testRestore_rejectsSchemaIncompatibleBackup_originalSurvives covers the schema-incompatible case (plus arbitrary-SQLite and valid-backup cases already existed). All BackupServiceTests pass.
<!-- SECTION:FINAL_SUMMARY:END -->
