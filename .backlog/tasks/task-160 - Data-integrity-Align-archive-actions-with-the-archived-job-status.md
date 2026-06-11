---
id: TASK-160
title: 'Data integrity: Align archive actions with the archived job status'
status: To Do
assignee: []
created_date: '2026-06-11 20:56'
labels:
  - audit
  - data-integrity
  - workflow
dependencies: []
references:
  - core/Services/JobService.swift
  - core/Models/Enums.swift
  - app/Views/Jobs/JobsView.swift
  - app/Views/Detail/JobDetailView.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`JobService.archive(jobID:)` currently sets status to `.passed`, while UI copy says the job is moved to Archived status and the domain model has `.archived`. This makes archived jobs indistinguishable from passed jobs in status filters and downstream workflows. Decide whether the command means archived or passed, then align service behavior, UI copy, filters, and tests.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Archive commands produce the status promised by the UI, or the UI is renamed to match the actual status transition.
- [ ] #2 Sidebar/status filters and availability/data-quality behavior handle the chosen status consistently.
- [ ] #3 Tests cover `archive(jobID:)` and at least one UI-facing archive path or view model equivalent.
<!-- AC:END -->
