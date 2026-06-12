---
id: TASK-236
title: 'Diagnostics: Retain recent toast errors for review'
status: Done
assignee: []
created_date: '2026-06-12 01:51'
updated_date: '2026-06-12 02:16'
labels:
  - diagnostics
  - ux
dependencies: []
references:
  - app/Views/Components/ToastView.swift
  - app/Views/Jobs/JobsView.swift
  - app/JobhuntApp.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Several failures are only shown as transient toasts that auto-dismiss after three seconds. Add a lightweight recent-errors history or route critical failures to a persistent surface so users can report them accurately.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Recent error toasts are retained in a diagnostics/history view or copied into the support bundle.
- [ ] #2 Critical operation failures remain accessible after the toast disappears.
- [ ] #3 Retained errors are sanitized and do not include sensitive raw data.
- [ ] #4 UI tests or focused tests cover at least one retained toast failure path.
<!-- AC:END -->
