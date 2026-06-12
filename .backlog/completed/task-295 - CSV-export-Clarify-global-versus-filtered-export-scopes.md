---
id: TASK-295
title: 'CSV export: Clarify global versus filtered export scopes'
status: Done
assignee: []
created_date: '2026-06-12 04:39'
updated_date: '2026-06-12 05:47'
labels:
  - audit
  - export
  - reporting
  - ux
dependencies: []
references:
  - app/Views/Jobs/JobsView.swift
  - app/JobhuntApp.swift
  - core/Services/ExportService.swift
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Jobs view export writes the current filtered list, while the global app menu export writes all jobs. Their labels are nearly identical, making it easy to export the wrong dataset. Make scope explicit in labels/default filenames and help text.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Jobs-view export label/default filename indicates it exports the current filtered list.
- [ ] #2 Global menu export label/default filename indicates it exports all jobs.
- [ ] #3 UI tests or command tests cover both export entry points' labels/help text.
<!-- AC:END -->
