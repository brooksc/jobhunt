---
id: TASK-341
title: 'MAS entitlements: Allow user-selected writes for export and backup flows'
status: Done
assignee: []
created_date: '2026-06-12 20:35'
updated_date: '2026-06-12 20:51'
labels:
  - audit
  - release
  - mas
  - sandbox
  - entitlements
dependencies: []
references:
  - config/entitlements/Jobhunt-MAS.entitlements
  - app/JobhuntApp.swift
  - app/Views/Settings/SettingsTab.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Jobhunt-MAS.entitlements grants user-selected read-only access, but the app writes CSV exports and backup files selected through save panels. MAS sandbox builds likely need user-selected read-write entitlement for these user-initiated save flows.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 MAS entitlements support all user-selected write flows required by CSV export and backup creation.
- [ ] #2 Manual MAS-signed validation confirms CSV export and backup save outside the container succeed.
- [ ] #3 Restore/import read flows continue to work under sandbox constraints.
<!-- AC:END -->
