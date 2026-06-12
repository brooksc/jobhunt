---
id: TASK-240
title: 'Data recovery: Add guided restore workflow for full-fidelity backups'
status: To Do
assignee: []
created_date: '2026-06-12 02:00'
labels:
  - backup
  - restore
  - recovery
dependencies: []
references:
  - core/Services/BackupService.swift
  - tests/CoreTests/BackupServiceTests.swift
  - tools/migrator/README.md
  - core/Models/ModelContainerFactory.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The app can create/open backup stores in tests, but users have no restore workflow. Add a guided restore path or documented safe manual flow that handles app shutdown, replacement, validation, and relaunch expectations.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Users can restore a full-fidelity backup through a guided app flow or clearly documented safe procedure.
- [ ] #2 Restore validates the selected backup before replacing current data.
- [ ] #3 The workflow protects the current store by creating a pre-restore backup or requiring explicit confirmation.
- [ ] #4 Help/README explains restore limitations and recovery steps.
<!-- AC:END -->
