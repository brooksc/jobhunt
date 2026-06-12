---
id: TASK-273
title: 'Fit scoring: Invalidate or rescore job scores when a resume changes'
status: To Do
assignee: []
created_date: '2026-06-12 03:33'
labels:
  - audit
  - resume
  - fit-scoring
  - data-consistency
dependencies: []
references:
  - core/Services/ResumeService.swift
  - core/Models/JobFitScore.swift
  - app/Views/Detail/JobDetailView.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Resume updates change the text used for fit scoring, but existing JobFitScore records remain visible as if current. Add an invalidation, stale marker, or automatic rescore path when resume text changes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Updating a resume marks related fit scores stale, deletes them, or queues rescoring according to an explicit product decision.
- [ ] #2 Job detail UI distinguishes stale scores from current scores if stale records are retained.
- [ ] #3 Tests cover editing a resume after scoring at least one job.
<!-- AC:END -->
