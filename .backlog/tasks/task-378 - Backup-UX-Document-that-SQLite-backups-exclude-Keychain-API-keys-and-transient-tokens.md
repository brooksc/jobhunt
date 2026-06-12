---
id: TASK-378
title: >-
  Backup UX: Document that SQLite backups exclude Keychain API keys and
  transient tokens
status: To Do
assignee: []
created_date: '2026-06-12 22:45'
labels:
  - audit
  - backup
  - privacy
  - documentation
dependencies: []
references:
  - core/Services/BackupService.swift
  - core/Settings/SettingsStore.swift
  - app/Views/Settings/SettingsTab.swift
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
BackupService documentation and UI imply full-fidelity data backup, but API keys are stored in Keychain and MCP tokens are transient files, so they are not included in the SQLite backup.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Backup and restore UI/help text clearly states that API keys must be re-entered after restore or migration when Keychain items are unavailable.
- [ ] #2 Developer documentation distinguishes SQLite-backed settings from Keychain secrets and transient MCP tokens.
- [ ] #3 A backup/restore smoke checklist verifies provider settings and API-key state after restore.
<!-- AC:END -->
