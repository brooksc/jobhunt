---
id: TASK-292
title: >-
  Dashboard: Base fit averages and recommendations on canonical per-resume score
  semantics
status: To Do
assignee: []
created_date: '2026-06-12 04:39'
labels:
  - audit
  - dashboard
  - fit-scoring
  - reporting
dependencies: []
references:
  - core/Services/JobStatusSummary.swift
  - app/Views/Dashboard/DashboardView.swift
  - core/Models/JobFitScore.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Dashboard average fit and recommendations use denormalized Job.fitScore, which may disagree with per-resume JobFitScore records or stale resume scores. Align dashboard metrics with the chosen canonical score semantics.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Dashboard average fit and recommendations use the canonical fit score definition, such as active-resume score or best current score.
- [ ] #2 Stale or invalidated fit scores are excluded or clearly marked.
- [ ] #3 Tests cover multiple resumes scored for one job and verify dashboard recommendation ordering.
<!-- AC:END -->
