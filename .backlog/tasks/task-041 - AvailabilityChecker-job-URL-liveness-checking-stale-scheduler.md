---
id: TASK-041
title: 'AvailabilityChecker: job-URL liveness checking + stale scheduler'
status: In Progress
assignee:
  - claude
created_date: '2026-06-07 22:45'
updated_date: '2026-06-08 02:05'
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
- [ ] #1 checkURL reproduces availability.js gone-detection (status codes, body patterns, redirects, missing title)
- [ ] #2 checkJobs / checkStaleJobs honor thresholds (21d default), per-run limit (25), and bounded concurrency
- [ ] #3 Jobs found gone are set not_available and emit jobUnavailable events
- [ ] #4 Ported availability.test.js passes as XCTest using a mocked URLProtocol
<!-- AC:END -->
