---
id: TASK-210
title: 'Persistence: Provide a full-fidelity backup/export path'
status: To Do
assignee: []
created_date: '2026-06-12 00:39'
labels:
  - persistence
  - backup
  - export
  - data-integrity
  - audit
dependencies: []
references:
  - core/Services/ExportService.swift
  - app/JobhuntApp.swift
  - app/Views/Jobs/JobsView.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The app currently exports a jobs CSV summary, but local-first user data includes captures, notes, resumes, sites, actions, fit scores, queue records, and settings. CSV export is not enough to recover the full database.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The app offers or documents a full-fidelity backup path that preserves all user-owned models.
- [ ] #2 The backup includes enough data to restore captures, jobs, related records, resumes, sites, and settings safely.
- [ ] #3 Tests or a documented verification procedure prove that a backup can be restored without losing core records.
<!-- AC:END -->
