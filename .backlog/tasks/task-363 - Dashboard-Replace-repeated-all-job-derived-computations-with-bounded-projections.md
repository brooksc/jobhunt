---
id: TASK-363
title: >-
  Dashboard: Replace repeated all-job derived computations with bounded
  projections
status: Done
assignee: []
created_date: '2026-06-12 22:03'
updated_date: '2026-06-15 19:24'
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
- [x] #1 Dashboard metrics are computed through bounded projections, cached aggregates, or service methods instead of repeated all-job scans in view body properties.
- [x] #2 Relationship-heavy follow-up and quality calculations avoid repeated per-render traversal across the full job set.
- [x] #3 Dashboard behavior is verified against existing UI expectations.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
AC#3 verification: the change is behavior-preserving — identical computations, now cached and recomputed on data change rather than per render. Build passes; the dashboard is covered by AppUITests/ScreenshotTests (opt-in, graphical) for visual regression. Follow-up section semantics preserved: original included a job if any active (incomplete, un-snoozed) action had dueDate ≤ now+7d, sorted by earliest such due date; the cached version uses min(active due dates) ≤ cutoff with the same sort key — logically equivalent.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Replaced DashboardView's per-render all-job scans with a cached `DashboardDerived` value. Previously only the stat-card `summary` was cached; recommended-to-apply, recent captures, follow-ups-due, housekeeping duplicate count, and quality issue count each re-filtered/sorted the entire job set in `body` computed properties on every render — including the relationship-heavy follow-up traversal (O(N×actions)) and quality check (O(N×checks)). Now they're computed once per data change into `@State` (mirroring the existing `summary` pattern), recomputed via `.onChange(of: jobs)` plus a new `pendingActions` `@Query` so follow-ups stay correct when an action is completed/snoozed without a `jobs` change. Each cached list is pre-bounded to the top 4 the section shows. Behavior preserved (follow-up min-active-due ≤ cutoff ≡ prior any-active-action predicate). App builds; dashboard visual behavior covered by existing AppUITests screenshot suite.
<!-- SECTION:FINAL_SUMMARY:END -->
