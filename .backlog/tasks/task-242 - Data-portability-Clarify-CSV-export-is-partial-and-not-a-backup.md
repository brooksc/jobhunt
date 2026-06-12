---
id: TASK-242
title: 'Data portability: Clarify CSV export is partial and not a backup'
status: To Do
assignee: []
created_date: '2026-06-12 02:01'
labels:
  - export
  - docs
  - ux
dependencies: []
references:
  - core/Services/ExportService.swift
  - app/Views/Jobs/JobsView.swift
  - app/JobhuntApp.swift
  - README.md
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CSV export only includes a subset of job-level fields, not raw captures, resumes, fit scores, events, settings, contacts, or queue history. Update the UI/help copy so users do not mistake CSV for a restorable backup.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 CSV export UI labels or confirmation copy clearly indicate it exports job list fields only.
- [ ] #2 Help/README distinguishes CSV export from full-fidelity backup.
- [ ] #3 CSV export docs list the exported scope or point to the backup command for full data preservation.
- [ ] #4 Tests for CSV export remain focused on the supported column set.
<!-- AC:END -->
