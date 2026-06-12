---
id: TASK-239
title: 'Data recovery: Expose full-fidelity backup from the app UI'
status: To Do
assignee: []
created_date: '2026-06-12 02:00'
labels:
  - backup
  - recovery
  - ux
dependencies: []
references:
  - core/Services/BackupService.swift
  - tests/CoreTests/BackupServiceTests.swift
  - app/Views/Settings/SettingsTab.swift
  - README.md
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
BackupService provides a tested SQLite VACUUM INTO backup path, but it is not wired into the app. Add a user-facing Back Up Data command that creates a full-fidelity backup rather than relying on manual file copying or partial CSV export.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A user-accessible Back Up Data action invokes BackupService against the production store.
- [ ] #2 The backup save panel uses a clear default filename and appropriate file extension.
- [ ] #3 Success and failure states are surfaced persistently enough for users to act on them.
- [ ] #4 Help/README documents the backup command and clarifies that it preserves all app data.
<!-- AC:END -->
