---
id: TASK-458
title: 'Data quality: Make high-severity reporting use high-severity issue kinds'
status: To Do
assignee: []
created_date: '2026-06-13 23:35'
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
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`QualityIssueKind` defines `isHighSeverity`, but `DataQualityView` currently counts high severity as jobs with three or more issue kinds. A job with multiple minor issues can be reported as high severity, while a single failed extraction may not be counted. High-severity metrics should either use the issue-kind severity flag or be renamed to match the current behavior.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 High-severity count is computed from `QualityIssueKind.isHighSeverity`, or the metric is renamed to explicitly mean jobs with three or more issues.
- [ ] #2 Data Quality UI labels and accessibility text match the implemented metric semantics.
- [ ] #3 Tests cover a single high-severity issue, multiple low-severity issues, and mixed issue kinds.
- [ ] #4 Dashboard and quality summaries remain consistent if both show high-severity or issue-count metrics.
<!-- AC:END -->
