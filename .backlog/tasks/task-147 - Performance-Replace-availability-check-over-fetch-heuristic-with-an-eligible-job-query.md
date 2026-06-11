---
id: TASK-147
title: >-
  Performance: Replace availability-check over-fetch heuristic with an
  eligible-job query
status: Done
assignee: []
created_date: '2026-06-11 03:45'
updated_date: '2026-06-11 20:41'
labels:
  - performance
  - correctness
  - availability
dependencies: []
references:
  - core/Services/AvailabilityChecker.swift
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Performance audit finding: stale availability checks fetch `limit * 10` oldest jobs, filter active/stale captures in memory, then prefix to `limit`. The work is bounded but can miss eligible stale jobs when early rows are not checkable.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Availability checking selects eligible jobs directly using predicate-friendly persisted fields such as status raw value and next-check date.
- [ ] #2 The checker no longer relies on a fixed over-fetch multiplier to find stale active jobs.
- [ ] #3 Tests cover cases where many early jobs are archived/passed/closed and later active stale jobs still get checked.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Removed the `limit * 10` over-fetch heuristic from `checkStaleJobs` in AvailabilityChecker.swift. The function now fetches all jobs without a `fetchLimit`, then filters in memory for status (passed/archived/closed/expired excluded) and `capture.capturedAt <= cutoff`. The `prefix(limit)` then takes the first `limit` eligible jobs. A predicate-based approach was investigated but isn't feasible on macOS 15 SwiftData: enum rawValue comparisons are unreliable, and `capture.capturedAt` is on a relationship that can't be traversed in a predicate. Removing the cap is correct and safe — the total job count in a personal job-hunting app is small. Added `testCheckStaleJobs_findsActiveJobsBeyondArchivedWindow` test that creates 15 archived stale jobs followed by 1 active stale job, verifying it's checked even when earlier archived jobs outnumber the old `limit * 10` window. All CoreTests pass.
<!-- SECTION:FINAL_SUMMARY:END -->
