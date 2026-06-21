---
id: TASK-580
title: 'Dashboard: align Quality Summary count with Data Quality view semantics'
status: To Do
assignee: []
created_date: '2026-06-21 03:11'
labels:
  - audit
  - dashboard
  - data-quality
  - workflow
dependencies: []
modified_files:
  - app/Views/Dashboard/DashboardView.swift
  - app/Views/Quality/DataQualityView.swift
  - core/Models/QualityIssue.swift
  - tests/CoreTests/QualityCheckerTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: Dashboard `qualityIssueCount` counts every job where `QualityChecker.issues(for:)` is non-empty, regardless of status or review state. `DataQualityView`, which the dashboard button opens, first filters out passed, archived, closed, and duplicate jobs, and by default also hides jobs with an existing `qualityReview`. This means the dashboard can show quality issues that disappear when the user clicks Review quality.

Why it matters: The dashboard card acts as a navigation promise. If it says there are N jobs with quality issues but the destination excludes those jobs, users lose trust in the aggregate and cannot reconcile or clear the count. The quality domain rule is duplicated between dashboard and Data Quality instead of being owned in one place.

Suggested implementation: Extract a shared quality visibility/query policy, e.g. `DataQualityScope.isIncluded(job:showReviewed:)`, and use it for both dashboard issue counts and `DataQualityView`. If the dashboard intentionally wants a broader all-time/all-status count, change the label and destination affordance to make that explicit, or provide separate counts for active unresolved vs total.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Dashboard Quality Summary count matches the default Data Quality view count after clicking Review quality.
- [ ] #2 Terminal-status jobs excluded from Data Quality do not inflate the dashboard actionable quality count.
- [ ] #3 Reviewed jobs hidden by default in Data Quality do not inflate the dashboard default count unless the dashboard label explicitly says it is total including reviewed.
- [ ] #4 Tests cover active issue, archived issue, duplicate issue, and reviewed issue count behavior through the shared policy.
<!-- AC:END -->
