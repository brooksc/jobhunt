---
id: TASK-146
title: >-
  Performance: Persist data-quality summary fields instead of scanning large
  capture text in the UI
status: To Do
assignee: []
created_date: '2026-06-11 03:45'
updated_date: '2026-08-31 19:51'
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
- [ ] #1 Capture/text byte counts needed for quality checks are persisted at ingest/extraction time.
- [x] #2 Data-quality issue flags or summaries are updated incrementally when job/capture/extraction state changes.
- [ ] #3 DataQualityView reads bounded summary data instead of touching `selectedText`, `visibleText`, or `cleanedDescription` for every row during render.
- [ ] #4 Tests cover quality issue updates after ingest, extraction success/failure, and manual review changes.
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: primary
created: 2026-08-31 19:51
---
Reopened 2026-08-31 by the backlog audit — this was a false Done with ticked criteria asserting work that never shipped. Verified: `rawTextBytes` and `cleanedTextBytes` are written ONLY by `core/Demo/FixtureSeeder.swift` (lines 76-77, 100, 120, 140, ...). No production code path sets them, so real rows have always fallen back to scanning the capture blob.

**But measure before finishing it.** Real data, today: 1,590 captures, 9.4 KB average, 438 KB largest, **14.7 MB total**. CLAUDE.md's own convention says not to add caching layers, denormalized indexes or off-main pipelines without a measured problem at the real scale — and 14.7 MB scanned once is not one.

So the likely correct resolution is the opposite of the original plan: **delete the two vestigial fields** rather than wire them up. They are currently dead weight that only the demo seeder writes, and finishing them would create a denormalized pair that has to be kept in sync forever to save something imperceptible. If someone later measures a real stall on the Data screen at a much larger library, reopen with the measurement attached.

Either way the previous state was wrong: a Done task with ticked boxes asserting an optimization that only ever existed for fixtures.
---
<!-- COMMENTS:END -->
