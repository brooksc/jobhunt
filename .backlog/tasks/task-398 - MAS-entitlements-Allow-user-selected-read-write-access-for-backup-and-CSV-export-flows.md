---
id: TASK-398
title: >-
  MAS entitlements: Allow user-selected read/write access for backup and CSV
  export flows
status: Done
assignee: []
created_date: '2026-06-12 23:34'
updated_date: '2026-06-15 04:10'
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
modified_files:
  - config/entitlements/Jobhunt-MAS.entitlements
  - .github/workflows/release-mas.yml
  - docs/MAS-VALIDATION.md
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The MAS entitlement file grants `com.apple.security.files.user-selected.read-only`, but the app writes user-selected files via NSSavePanel for backups and CSV export. Use the appropriate read/write entitlement and add a release smoke check so MAS builds can save backup/export files under sandboxing.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 MAS entitlements include user-selected read/write access required for save-panel writes.
- [x] #2 MAS validation docs include backup and CSV export write checks.
- [x] #3 A MAS build smoke check verifies the expected file-access entitlement is present.
- [ ] #4 Backup and CSV export flows are manually or automatically verified under sandboxed execution.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Changed the MAS entitlement from com.apple.security.files.user-selected.read-only to .read-write so NSSavePanel writes (store backup in SettingsTab, CSV export in JobsView) succeed under sandboxing. Extended the release-mas.yml "Smoke check MAS artifact" step to assert the signed app exposes files.user-selected.read-write and does NOT expose read-only. Added a "User-selected file writes" section to docs/MAS-VALIDATION.md with the automated check and a manual backup/CSV-export test procedure. AC#4 (run the backup + CSV flows under a real sandboxed signed build) still requires a MAS-signed build run on signing infra — the automated entitlement check and manual procedure are in place to gate it.
<!-- SECTION:FINAL_SUMMARY:END -->
