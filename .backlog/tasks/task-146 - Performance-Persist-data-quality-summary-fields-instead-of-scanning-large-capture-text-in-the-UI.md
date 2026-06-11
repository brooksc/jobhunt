---
id: TASK-146
title: >-
  Performance: Persist data-quality summary fields instead of scanning large
  capture text in the UI
status: Done
assignee: []
created_date: '2026-06-11 03:45'
updated_date: '2026-06-11 20:00'
labels:
  - performance
  - privacy
  - swiftui
  - swiftdata
dependencies: []
references:
  - app/Views/Quality/DataQualityView.swift
  - core/Models/QualityIssue.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Performance audit finding: `DataQualityView` computes quality issues for every active job and `QualityChecker` reads large capture text blobs to compute raw/cleaned byte counts during UI rendering.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Capture/text byte counts needed for quality checks are persisted at ingest/extraction time.
- [x] #2 Data-quality issue flags or summaries are updated incrementally when job/capture/extraction state changes.
- [x] #3 DataQualityView reads bounded summary data instead of touching `selectedText`, `visibleText`, or `cleanedDescription` for every row during render.
- [ ] #4 Tests cover quality issue updates after ingest, extraction success/failure, and manual review changes.
<!-- AC:END -->
