---
id: TASK-291
title: 'Dashboard: Use QualityChecker for dashboard quality count'
status: To Do
assignee: []
created_date: '2026-06-12 04:39'
labels:
  - audit
  - dashboard
  - data-quality
  - reporting
dependencies: []
references:
  - core/Services/JobStatusSummary.swift
  - core/Models/QualityIssue.swift
  - app/Views/Dashboard/DashboardView.swift
  - app/Views/Quality/DataQualityView.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Dashboard quality summary uses a smaller heuristic than the Data Quality view, so it can show zero issues while Data Quality still has missing location/work mode/salary, pending extraction, short text, or stale extraction issues. Reuse QualityChecker semantics or clearly rename the dashboard metric.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Dashboard quality count uses the same QualityChecker issue semantics as Data Quality, or the metric label explicitly describes the narrower heuristic.
- [ ] #2 Reviewed/ignored quality issues are handled consistently between dashboard and Data Quality.
- [ ] #3 Tests cover a job with non-dashboard-only issues such as missing salary or stale extraction.
<!-- AC:END -->
