---
id: TASK-328
title: 'Backup restore: Make store replacement atomic'
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
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
BackupService.restore removes the current store and then copies the backup into place, despite comments describing an atomic replace. If the copy fails after removal, the app can be left without a usable store file.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Restore copies to a temporary file or uses FileManager replacement semantics so the original store remains available if replacement fails.
- [ ] #2 Restore failure tests simulate copy/replace failure and verify the previous store still exists.
- [ ] #3 The implementation and comments agree on the actual replacement guarantees.
<!-- AC:END -->
