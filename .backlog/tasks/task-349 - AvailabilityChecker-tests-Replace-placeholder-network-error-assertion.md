---
id: TASK-349
title: 'AvailabilityChecker tests: Replace placeholder network-error assertion'
status: Done
assignee: []
created_date: '2026-06-12 20:40'
updated_date: '2026-06-12 20:58'
labels:
  - audit
  - tests
  - availability
dependencies: []
references:
  - tests/CoreTests/AvailabilityCheckerTests.swift
  - core/Services/AvailabilityChecker.swift
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
testReturnsErrorOnNetworkFailure contains XCTAssertTrue(true) and states the behavior is indirectly covered. The named network-error behavior is not actually verified.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The test uses a URLProtocol/session stub that throws or otherwise simulates a network failure.
- [ ] #2 The assertion verifies AvailabilityChecker returns the expected .error result and diagnostic reason.
- [ ] #3 No placeholder assertions remain for named behavior.
<!-- AC:END -->
