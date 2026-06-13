---
id: TASK-457
title: 'Data quality: Separate job counts from issue occurrence counts'
status: To Do
assignee: []
created_date: '2026-06-13 23:35'
labels:
  - data-quality
  - ux
  - reporting
dependencies: []
references:
  - app/Views/Quality/DataQualityView.swift
  - core/Models/QualityIssue.swift
  - tests/CoreTests/QualityCheckerTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The Data Quality UI labels `issueRows.count` as "Total issues", but that collection contains one row per job with at least one issue. The grouped list then repeats the same job under each issue kind. Reporting should distinguish jobs with issues from total issue occurrences so dashboard and quality views communicate accurate metrics.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Data quality summary exposes separate counts for jobs with issues and total issue occurrences.
- [ ] #2 Grouped issue-kind counts are derived from issue occurrences, not ambiguous job-row counts.
- [ ] #3 UI labels clearly distinguish jobs from issues wherever counts are displayed.
- [ ] #4 Tests cover a job with multiple issue kinds and verify both job count and issue occurrence count.
<!-- AC:END -->
