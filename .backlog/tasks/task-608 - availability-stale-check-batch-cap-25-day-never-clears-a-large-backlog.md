---
id: TASK-608
title: 'availability: stale-check batch cap (25/day) never clears a large backlog'
status: To Do
assignee: []
created_date: '2026-07-21 23:40'
labels:
  - availability
  - tech-debt
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`AvailabilityChecker.checkStaleJobs` / `maybeFindStaleGoneJobs` / `maybeRunStaleCheck` hardcode `limit: 25` (`AvailabilityChecker.swift:630,700,742`) and the auto-check interval defaults to 1 day. With hundreds of stale pursuing/applied jobs (user currently has 285 total), only 25 get re-verified per day, so the full set is never re-checked.

Also the eligible-fetch over-fetches by a fixed multiple then filters in memory (`fetchLimit = limit*4` line 656, `limit*2` line 664) and `.prefix(limit)` truncates — so if more than limit*2 legacy (nil capturedAtDenormalized) rows exist, eligible legacy jobs past the cut are silently invisible to the checker.

Needs a considered policy, not just a bigger number: e.g. scale the batch by backlog size, make it a setting, or run until the backlog is drained within a time/cost budget. Also de-duplicate the `10`/`limit` magic numbers (maxConcurrent at :548, inFlight guard at :481).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A large stale backlog is fully re-checked over a bounded, reasonable window (not capped at 25/day forever)
- [ ] #2 Legacy (nil capturedAtDenormalized) rows past the over-fetch multiple are not silently skipped
- [ ] #3 Batch/concurrency magic numbers are named constants or settings, not duplicated literals
<!-- AC:END -->
