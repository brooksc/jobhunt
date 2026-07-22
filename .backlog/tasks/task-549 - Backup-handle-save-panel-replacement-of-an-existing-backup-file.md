---
id: TASK-549
title: 'Backup: handle save-panel replacement of an existing backup file'
status: Done
assignee: []
created_date: '2026-06-19 22:19'
updated_date: '2026-07-22 01:33'
labels:
  - audit
  - backup
  - ux
  - file-io
dependencies: []
references:
  - core/Services/BackupService.swift
  - app/Views/Settings/SettingsTab.swift
  - tests/CoreTests/BackupServiceTests.swift
priority: medium
ordinal: 13000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: `BackupService.backup` uses SQLite `VACUUM INTO`, and its own doc comment says the destination file must not already exist. The Settings backup UI uses `NSSavePanel`, which can return an existing file path after the user confirms replacement. In that case, `VACUUM INTO` fails instead of replacing the file the user selected.

Why this matters: backup is a trust-critical workflow. If a user chooses an existing backup to replace, the UI has already accepted that intent, but the service reports a low-level backup failure. This is a small file-boundary mismatch between the save-panel contract and SQLite's `VACUUM INTO` contract.

Suggested implementation: write to a unique temporary file in the destination directory, validate it, then atomically replace/move it to the requested destination. Alternatively, remove the existing destination only after a staged backup has succeeded, but avoid deleting the user's existing backup before a new valid backup exists. Keep the current no-live-store-mutation property.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Backing up to a new destination still succeeds as before.
- [ ] #2 Backing up to an existing destination selected via save panel replaces it only after a new backup has been successfully created.
- [ ] #3 If backup creation fails, the pre-existing backup file remains intact.
- [ ] #4 Temporary/staged backup files are cleaned up on success and failure.
- [ ] #5 Tests cover existing-destination success and failure-preserves-existing behavior.
- [ ] #6 User-facing errors no longer expose the raw `VACUUM INTO` file-exists failure for normal replacement intent.
<!-- AC:END -->
