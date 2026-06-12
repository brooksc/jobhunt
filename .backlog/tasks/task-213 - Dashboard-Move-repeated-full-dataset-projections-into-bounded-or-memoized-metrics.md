---
id: TASK-213
title: >-
  Dashboard: Move repeated full-dataset projections into bounded or memoized
  metrics
status: To Do
assignee: []
created_date: '2026-06-12 00:41'
labels:
  - performance
  - dashboard
  - swiftui
  - audit
dependencies: []
references:
  - app/Views/Dashboard/DashboardView.swift
  - app/Views/Dashboard/DashboardMetrics.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
DashboardView queries all jobs and recomputes multiple counts, filters, and sorts in computed view sections on render. This creates repeated full-dataset work as the job history grows.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Dashboard metrics are computed once per relevant data change, not repeatedly per view section render.
- [ ] #2 Top-N sections use bounded projection helpers or query-backed data where practical.
- [ ] #3 Tests cover dashboard metric helpers for representative datasets.
<!-- AC:END -->
