---
id: TASK-588
title: 'Server: add test coverage for /api/jobs/by-url endpoint'
status: Done
assignee: []
created_date: '2026-07-02 21:51'
updated_date: '2026-07-22 01:14'
labels: []
dependencies: []
references:
  - 'server/swift/JobhuntServer.swift:638'
  - tests/ServerTests/JobhuntServerTests.swift
priority: low
ordinal: 37000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Problem:** `/api/jobs/by-url` (`JobhuntServer.swift:638–660`) is the only extension-facing endpoint with zero test coverage in `ServerTests`. All other endpoints have at least happy-path coverage.

**How to fix:** Add cases to `JobhuntServerTests` (follow the existing `sharedServer` pattern):
1. Valid URL that matches a known job → returns `{"job_number": N}` with 200.
2. URL not found → returns 404.
3. Missing `url` query parameter → returns 400.
4. Malformed URL string (e.g. spaces, no scheme) → verify it doesn't crash and returns 400 or 404 consistently.
5. Multiple `url=` query parameters → verify only the first is used (documents current behavior per `HTTPRequest.queryValue(for:)`).

No new infrastructure needed — the existing `sharedServer` fixture and `makeRequest` helper cover everything required.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 5 test cases added covering: hit, miss, missing param, malformed URL, duplicate param
- [ ] #2 Tests run as part of the ServerTests fast-gate target
<!-- AC:END -->
