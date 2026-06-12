---
id: TASK-260
title: 'Persistence: Add guided restore or start-fresh flow to store recovery UI'
status: Done
assignee: []
created_date: '2026-06-12 02:52'
updated_date: '2026-06-12 03:09'
labels:
  - audit
  - persistence
  - recovery
  - backup
dependencies: []
references:
  - app/JobhuntApp.swift
  - app/Views/Components/StoreRecoveryView.swift
  - core/Services/BackupService.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
When the SwiftData container fails to open, the app shows a recovery view that only opens the data folder or quits. `BackupService.restore` exists, but the user has no guided in-app path to choose a backup, create a pre-restore safety copy, restore it, and relaunch or start fresh.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Store recovery UI supports guided restore from a valid backup or an explicit start-fresh path.
- [ ] #2 Restore flow creates a best-effort safety backup of existing store files before replacement when possible.
- [ ] #3 The app terminates or relaunches cleanly after restore so no live container points at replaced files.
- [ ] #4 Tests cover backup validation and restore failure messaging where feasible.
<!-- AC:END -->
