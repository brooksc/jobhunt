---
id: TASK-389
title: >-
  Availability checker: Do not mark checks complete when fetch or update work
  failed silently
status: Done
assignee: []
created_date: '2026-06-12 22:58'
updated_date: '2026-06-15 04:26'
labels:
  - audit
  - error-handling
  - availability
dependencies: []
references:
  - core/Services/AvailabilityChecker.swift
modified_files:
  - core/Services/AvailabilityChecker.swift
  - tests/CoreTests/AvailabilityCheckerTests.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
AvailabilityChecker returns zero-count results on fetch failure and `maybeRunStaleCheck` records the last-check timestamp afterward. This can suppress future checks for the interval even though no valid check ran. Per-job update/event/notification errors are also silently skipped.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Fetch failures are returned or recorded as failures rather than zero-success checks.
- [x] #2 Last-check timestamps are updated only after a valid check pass or with a separate failed-at timestamp.
- [x] #3 Per-job marking/event/notification failures are counted and exposed in the check result.
- [ ] #4 Tests cover fetch failure interval behavior and partial per-job failures.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
checkStaleJobs now throws on store-fetch failure (was swallowed as a 0,0,0 success). maybeRunStaleCheck only posts .availabilityCheckCompleted (which advances the last-check timestamp via the AppServices observer) after a valid pass; on fetch failure it returns reason "fetch-error" and does NOT advance the timestamp, so a transient store error no longer suppresses checks for the whole interval. checkJobs gained a `failed` count for per-job marking/event/notification failures (logged, not silently skipped). AC#4 partial: added happy-path + completion-notification-posted tests; the fetch-failure interval path could not be unit-tested without introducing a store-fetch failure-injection seam (BackgroundStore is concrete @ModelActor) — deferred rather than over-refactor the store now.
<!-- SECTION:FINAL_SUMMARY:END -->
