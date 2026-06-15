---
id: TASK-458
title: 'Data quality: Make high-severity reporting use high-severity issue kinds'
status: Done
assignee: []
created_date: '2026-06-13 23:35'
updated_date: '2026-06-15 18:10'
labels:
  - data-quality
  - ux
  - reporting
dependencies: []
references:
  - core/Models/QualityIssue.swift
  - app/Views/Quality/DataQualityView.swift
  - app/Views/Dashboard/DashboardView.swift
  - tests/CoreTests/QualityCheckerTests.swift
modified_files:
  - core/Models/QualityIssue.swift
  - app/Views/Quality/DataQualityView.swift
  - tests/CoreTests/QualityCheckerTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`QualityIssueKind` defines `isHighSeverity`, but `DataQualityView` currently counts high severity as jobs with three or more issue kinds. A job with multiple minor issues can be reported as high severity, while a single failed extraction may not be counted. High-severity metrics should either use the issue-kind severity flag or be renamed to match the current behavior.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 High-severity count is computed from `QualityIssueKind.isHighSeverity`, or the metric is renamed to explicitly mean jobs with three or more issues.
- [x] #2 Data Quality UI labels and accessibility text match the implemented metric semantics.
- [x] #3 Tests cover a single high-severity issue, multiple low-severity issues, and mixed issue kinds.
- [x] #4 Dashboard and quality summaries remain consistent if both show high-severity or issue-count metrics.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added QualityIssue.isHighSeverity (true if any of the job's issue kinds is high-severity via QualityIssueKind.isHighSeverity). DataQualityView.highSeverityCount now uses it instead of severity >= 3, so a single high-severity issue (e.g. extractionFailed/missingTitle) counts and three minor issues don't (AC#1). The metric label/accessibility is now "High severity" (no longer "(3+)"), matching the semantics (AC#2). Dashboard shows jobs-with-quality-issues (a job count, labeled as such) so the two views stay consistent (AC#4). Tests cover single high kind, multiple low kinds, and mixed (AC#3).
<!-- SECTION:FINAL_SUMMARY:END -->
