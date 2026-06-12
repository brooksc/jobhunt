---
id: TASK-329
title: 'Settings restore: Treat pre-restore backup failure as blocking'
status: To Do
assignee: []
created_date: '2026-06-12 20:05'
labels:
  - audit
  - backup
  - restore
  - settings
  - data-loss
dependencies: []
references:
  - app/Views/Settings/SettingsTab.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Settings restore promises an automatic pre-restore backup, but performRestore uses try? for BackupService.backup and proceeds with destructive restore even if that backup fails.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Restore does not proceed silently when the pre-restore backup fails.
- [ ] #2 The user receives a clear error and can retry or explicitly choose a separate recovery action if supported.
- [ ] #3 Tests or focused validation cover backup failure before restore.
<!-- AC:END -->
