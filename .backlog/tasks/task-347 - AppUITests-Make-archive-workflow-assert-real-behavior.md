---
id: TASK-347
title: 'AppUITests: Make archive workflow assert real behavior'
status: To Do
assignee: []
created_date: '2026-06-12 20:39'
labels:
  - audit
  - tests
  - ui-tests
  - workflow
dependencies: []
references:
  - tests/AppUITests/WorkflowUITests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
testArchive_seededJob_movesJobToArchived currently uses waitUntil { true } after clicking Archive and records a non-failing activity if the archive menu item is absent. The test can pass without proving archive behavior.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The archive test fails if the archive action is absent.
- [ ] #2 After archiving, the test verifies an observable state change such as row removal, status change, or presence in the expected archived/status view.
- [ ] #3 The test avoids unconditional true assertions and non-failing known-skip branches for required behavior.
<!-- AC:END -->
