---
id: TASK-103
title: Route data-quality mutations through one service boundary
status: To Do
assignee: []
created_date: '2026-06-10 20:49'
labels:
  - architecture
  - audit
  - data-quality
  - swiftdata
dependencies: []
references:
  - core/Services/JobService.swift
  - app/Views/Quality/DataQualityView.swift
  - core/Services/BackgroundStore.swift
  - tests/CoreTests/JobServiceTests.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Architecture audit finding: data-quality review workflows are split between direct SwiftData writes in `DataQualityView` and service methods in `JobService`. The two paths already differ behaviorally: the service path contains an unsafe broad delete while the UI path deletes the selected review object directly. Make data-quality review writes use a single Core service boundary so callers share the same behavior and tests.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Mark reviewed, clear review, and queue re-extraction actions in `DataQualityView` call service methods instead of mutating `modelContext` directly.
- [ ] #2 The service implementation clears only the requested job's review and preserves unrelated reviews.
- [ ] #3 Regression tests cover data-quality mark, clear, and queue-reextraction service behavior.
- [ ] #4 The UI still updates via SwiftData observation after service writes.
<!-- AC:END -->
