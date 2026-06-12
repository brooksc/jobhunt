---
id: TASK-258
title: >-
  Persistence: Replace weak capture raw-hash uniqueness test with real invariant
  coverage
status: To Do
assignee: []
created_date: '2026-06-12 02:51'
labels:
  - audit
  - persistence
  - tests
dependencies: []
references:
  - tests/CoreTests/ModelRoundTripTests.swift
  - core/Models/Capture.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`testCaptureRawHashUniqueness` inserts duplicate raw hashes but only asserts the fetched count is greater than or equal to one. Because `Capture.rawHash` is not currently marked unique, the test does not verify the invariant described by its name or comments.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The raw-hash uniqueness test asserts the actual expected behavior for duplicate persisted captures.
- [ ] #2 The test uses a file-backed store if in-memory SwiftData behavior differs from SQLite-backed behavior.
- [ ] #3 Test names and comments accurately describe what is being verified.
<!-- AC:END -->
