---
id: TASK-096
title: Fix DataQualityReview clearing so it only deletes the selected job review
status: To Do
assignee: []
created_date: '2026-06-10 07:49'
labels:
  - bug
  - audit
  - data-loss
dependencies: []
references:
  - core/Services/JobService.swift
  - core/Services/BackgroundStore.swift
  - app/Views/Quality/DataQualityView.swift
  - tests/CoreTests/JobServiceTests.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Audit finding: `JobService.clearDataQualityReview(jobID:)` currently reaches the selected job's review but then calls `BackgroundStore.delete(DataQualityReview.self, predicate: nil)`, which deletes every `DataQualityReview` row. Preserve the intended behavior of clearing only the requested job's review and make the destructive store API harder to misuse.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Clearing a data-quality review through `JobService.clearDataQualityReview(jobID:)` removes only the review attached to the requested job.
- [ ] #2 A regression test creates at least two reviewed jobs, clears one via `JobService`, and verifies the other review still exists.
- [ ] #3 The generic store deletion API no longer makes accidental all-row deletion easy from call sites that intend targeted deletion.
- [ ] #4 Existing CoreTests pass after the change.
<!-- AC:END -->
