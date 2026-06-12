---
id: TASK-398
title: >-
  MAS entitlements: Allow user-selected read/write access for backup and CSV
  export flows
status: To Do
assignee: []
created_date: '2026-06-12 23:34'
labels:
  - audit
  - release
  - mas
  - sandbox
  - export
  - backup
dependencies: []
references:
  - config/entitlements/Jobhunt-MAS.entitlements
  - app/Views/Settings/SettingsTab.swift
  - app/JobhuntApp.swift
  - core/Services/ExportService.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The MAS entitlement file grants `com.apple.security.files.user-selected.read-only`, but the app writes user-selected files via NSSavePanel for backups and CSV export. Use the appropriate read/write entitlement and add a release smoke check so MAS builds can save backup/export files under sandboxing.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 MAS entitlements include user-selected read/write access required for save-panel writes.
- [ ] #2 MAS validation docs include backup and CSV export write checks.
- [ ] #3 A MAS build smoke check verifies the expected file-access entitlement is present.
- [ ] #4 Backup and CSV export flows are manually or automatically verified under sandboxed execution.
<!-- AC:END -->
