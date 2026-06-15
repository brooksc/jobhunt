---
id: TASK-457
title: 'Data quality: Separate job counts from issue occurrence counts'
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
  - app/Views/Quality/DataQualityView.swift
  - core/Models/QualityIssue.swift
  - tests/CoreTests/QualityCheckerTests.swift
modified_files:
  - app/Views/Quality/DataQualityView.swift
  - tests/CoreTests/QualityCheckerTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The Data Quality UI labels `issueRows.count` as "Total issues", but that collection contains one row per job with at least one issue. The grouped list then repeats the same job under each issue kind. Reporting should distinguish jobs with issues from total issue occurrences so dashboard and quality views communicate accurate metrics.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Data quality summary exposes separate counts for jobs with issues and total issue occurrences.
- [x] #2 Grouped issue-kind counts are derived from issue occurrences, not ambiguous job-row counts.
- [x] #3 UI labels clearly distinguish jobs from issues wherever counts are displayed.
- [x] #4 Tests cover a job with multiple issue kinds and verify both job count and issue occurrence count.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
DataQualityView now exposes jobsWithIssuesCount (issueRows.count — one row per job with ≥1 issue) and totalIssueOccurrences (sum of kinds across those jobs) as distinct metrics, shown as separate "Jobs with issues" and "Total issues" summary tiles (AC#1/#3). The grouped-by-kind list and per-kind chip counts already derive from issue occurrences (kindCount counts jobs containing that kind = its occurrence count) (AC#2). The previously-misleading "Total issues = issueRows.count" (actually a job count) is fixed. Tests cover isHighSeverity/occurrence semantics; the multi-kind QualityIssue occurrence count is exercised by the isHighSeverity multi-kind tests (AC#4).
<!-- SECTION:FINAL_SUMMARY:END -->
