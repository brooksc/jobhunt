---
id: TASK-363
title: >-
  Dashboard: Replace repeated all-job derived computations with bounded
  projections
status: To Do
assignee: []
created_date: '2026-06-12 22:03'
labels:
  - audit
  - performance
  - dashboard
dependencies: []
references:
  - app/Views/Dashboard/DashboardView.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
DashboardView fetches all jobs and repeatedly filters/sorts relationship-heavy data for recommendations, recent captures, follow-ups, quality, and charts.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Dashboard metrics are computed through bounded projections, cached aggregates, or service methods instead of repeated all-job scans in view body properties.
- [ ] #2 Relationship-heavy follow-up and quality calculations avoid repeated per-render traversal across the full job set.
- [ ] #3 Dashboard behavior is verified against existing UI expectations.
<!-- AC:END -->
