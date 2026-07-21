---
id: TASK-583
title: 'Dashboard: refresh date-window metrics when the calendar day changes'
status: To Do
assignee: []
created_date: '2026-06-21 03:11'
updated_date: '2026-07-21 22:59'
labels:
  - audit
  - dashboard
  - date-time
  - metrics
dependencies: []
modified_files:
  - app/Views/Dashboard/DashboardView.swift
  - app/Views/Dashboard/DashboardMetrics.swift
  - tests/CoreTests/JobStatusSummaryTests.swift
priority: low
ordinal: 33000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: Dashboard date-window metrics are computed with `Date()` during view initialization or model-change recomputation. The 30-day captures query is initialized once using a fixed `thirtyDaysAgo`; `DashboardMetrics.buildDailyActivity`, follow-up due windows, site overdue flags, and relative labels also depend on the current date. If the app stays open across midnight or long enough for a due window to change without any model mutation, dashboard sections can remain stale until a data change or remount.

Why it matters: Dashboard is a current-state surface. Date-sensitive cards such as Daily Activity, Follow-ups Due, Sites due, and relative due labels can be wrong precisely when a user checks the app the next day. The current design hides time as an implicit dependency rather than modeling it as an input.

Suggested implementation: Add an explicit dashboard clock/day token, updated on appear and at the next local midnight (or periodically at low frequency), and use it to rebuild date-window queries/projections. For SwiftData query limitations, avoid baking a static date into `@Query` init for rolling windows, or recompute the window from an unfiltered/appropriately filtered capture set using the current day token.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Daily Activity's 30-day window advances after local midnight without requiring a capture/job mutation.
- [ ] #2 Follow-up due windows and site overdue/due labels refresh when the calendar day changes.
- [ ] #3 The dashboard has a testable date input for pure metric helpers instead of calling `Date()` in every calculation path.
- [ ] #4 Tests cover a metric before and after a simulated day boundary.
<!-- AC:END -->
