---
id: TASK-198
title: 'Extension: Add focused tests for capture and preflight behavior'
status: To Do
assignee: []
created_date: '2026-06-11 23:47'
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
- [ ] #1 capture.js has focused tests for preflight rendering and page-derived text handling.
- [ ] #2 Extension tests cover Greenhouse timeout/failure fallback, quota failure, and queue concurrency behavior.
- [ ] #3 Service-worker contract tests continue to pass with the expanded coverage.
<!-- AC:END -->
