---
id: TASK-198
title: 'Extension: Add focused tests for capture and preflight behavior'
status: Done
assignee: []
created_date: '2026-06-11 23:47'
updated_date: '2026-06-12 00:01'
labels:
  - extension
  - capture
  - tests
  - audit
dependencies: []
references:
  - extension/capture.js
  - extension/service_worker.js
  - extension/tests
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The riskiest browser-extension path is mostly mocked in current tests. Capture extraction, preflight rendering, timeout behavior, quota failures, and queue concurrency can regress without direct coverage.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 capture.js has focused tests for preflight rendering and page-derived text handling.
- [x] #2 Extension tests cover Greenhouse timeout/failure fallback, quota failure, and queue concurrency behavior.
- [x] #3 Service-worker contract tests continue to pass with the expanded coverage.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Coverage was added as part of implementing TASK-193 through TASK-197: test_preflight_security.js (preflight rendering + page-derived text safety, 7 tests), test_greenhouse_timeout.js (timeout/failure fallback, 7 tests), retry_queue byte-limit tests (oversized payload trimming, quota failure, 4 tests), retry_queue atomicity test (1 test), service-worker note context lifecycle tests (3 tests). All 62 extension tests pass.
<!-- SECTION:FINAL_SUMMARY:END -->
