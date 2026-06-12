---
id: TASK-275
title: 'Fit scoring: Reconcile job-level fitScore with per-resume fit scores'
status: Done
assignee: []
created_date: '2026-06-12 03:34'
updated_date: '2026-06-12 03:44'
labels:
  - audit
  - fit-scoring
  - search
  - data-model
dependencies: []
references:
  - core/Services/BackgroundStore.swift
  - core/Models/Job.swift
  - app/Views/Jobs/JobsView.swift
  - app/Views/Detail/JobDetailView.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
BackgroundStore overwrites Job.fitScore on every successful score, while the detail UI treats Job.fitScores as the canonical per-resume history. Define whether Job.fitScore means latest active-resume score, best score, or legacy cache, and update filtering/search logic accordingly.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Job.fitScore has a documented and tested meaning relative to JobFitScore records.
- [ ] #2 Search/filter behavior uses the intended score, such as active-resume or best-resume score.
- [ ] #3 Tests cover multiple resumes scored for one job and verify the denormalized value/search result.
<!-- AC:END -->
