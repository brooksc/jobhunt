---
id: TASK-041
title: 'AvailabilityChecker: job-URL liveness checking + stale scheduler'
status: Done
assignee:
  - claude
created_date: '2026-06-07 22:45'
updated_date: '2026-06-08 02:15'
labels:
  - swift-rewrite
  - core
milestone: m-1
dependencies:
  - TASK-034
documentation:
  - swift-plan.md
  - server/availability.js
  - tests/unit/availability.test.js
priority: medium
ordinal: 1800
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: Port job-availability checking — detecting when a saved/applied job is no longer live, plus the periodic stale-check scheduler.

## Read first
- swift-plan.md §9 (AvailabilityChecker), §6.1 (Job model: status not_available), §10.5 (job-unavailable notification).
- Legacy server/availability.js — checkUrl (404/410, "no longer available" body patterns, bad-redirect/missing-title detection), checkJobsAvailability (parallel over non-archived jobs), checkStaleJobsAvailability (jobs untouched N days, default 21, ≤25/run), maybeRunStaleAvailabilityCheck (interval-gated auto-run).
- tests/unit/availability.test.js for expected detection behavior.

## Implement (core/Services/AvailabilityChecker.swift)
- URLSession-based `checkURL` reproducing the gone-detection heuristics.
- `checkJobs` (parallel, bounded concurrency) and `checkStaleJobs` with the same thresholds/limits, reading settings (interval/threshold) via SettingsStore.
- On a job found gone: set status not_available and emit a `jobUnavailable` domain event (the app layer turns this into a notification — see the platform-integration task). Use the BackgroundStore actor for writes.

## Dependencies
Depends on task-034 (models). Reads settings (task-035) if available. Emits events consumed by platform integration.

## Tests (CoreTests)
- Port tests/unit/availability.test.js: 404/410 and body-pattern detection, redirect/missing-title cases, stale selection + per-run limit. Mock URLProtocol for HTTP responses.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 checkURL reproduces availability.js gone-detection (status codes, body patterns, redirects, missing title)
- [x] #2 checkJobs / checkStaleJobs honor thresholds (21d default), per-run limit (25), and bounded concurrency
- [x] #3 Jobs found gone are set not_available and emit jobUnavailable events
- [x] #4 Ported availability.test.js passes as XCTest using a mocked URLProtocol
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Implemented AvailabilityChecker.swift in core/Services/ with full port of server/availability.js behavior:

- URLAvailabilityResult enum (.available, .gone(reason:), .error(_))
- checkURL(_ url:, title:, session:): URLSession-based HEAD+GET with 12s timeout, 404/410 detection, 15 gone body patterns, redirect-to-non-job heuristic (root/jobs/careers/company paths), missing-title-after-redirect detection. Timeout and network errors treated as available (matches JS behavior).
- checkJobs(_ jobs:, store:, session:): parallel bounded concurrency (max 10) via TaskGroup with lightweight Sendable value types to avoid SwiftData actor isolation issues. Gone jobs updated via BackgroundStore and jobUnavailable notification posted.
- checkStaleJobs(store:, staleDays:, limit:): fetches jobs older than cutoff (default 21d), limits to 25/run, in-memory filtering to avoid SwiftData enum predicate limitations on macOS 15.
- maybeRunStaleCheck(store:, settings:, session:): reads availabilityAutoCheckEnabled, availabilityAutoCheckIntervalDays, availabilityStaleDays from SettingsStore; posts availabilityCheckCompleted notification for app layer to update last-check timestamp.

15 XCTest cases in Tests/CoreTests/AvailabilityCheckerTests.swift porting the JS test suite: 404/410 detection, body pattern detection, redirect heuristics (company page, missing title, canonical redirect, search page, cross-domain), URL normalization, isMeaningfulTitle, checkJobs with BackgroundStore (skip archived/notAvailable, mark gone, emit notification), checkStaleJobs stale selection, maybeRunStaleCheck disabled/interval/elapsed cases. All 96 CoreTests pass (81 pre-existing + 15 new).
<!-- SECTION:FINAL_SUMMARY:END -->
