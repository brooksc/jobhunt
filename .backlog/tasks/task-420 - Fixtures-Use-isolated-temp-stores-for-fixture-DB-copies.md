---
id: TASK-420
title: 'Fixtures: Use isolated temp stores for fixture DB copies'
status: To Do
assignee: []
created_date: '2026-06-13 04:21'
labels:
  - audit
  - fixtures
  - tests
dependencies: []
references:
  - core/Models/ModelContainerFactory.swift
  - docs/test-db-spec.md
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`ModelContainerFactory.fixture(copying:)` copies every fixture source into a fixed temp path under `NSTemporaryDirectory()/JobhuntFixture/jobhunt-fixture.store`, deleting any prior store first. This makes parallel test runs and simultaneous local launches race with each other, and it does not satisfy the test DB spec's per-class/per-run isolation goal.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Fixture DB copies use a unique destination per test run, process, or caller-provided isolation scope instead of one global temp file.
- [ ] #2 Parallel fixture consumers cannot delete or overwrite each other's temp stores.
- [ ] #3 The fixture API makes ownership and cleanup expectations explicit enough for UI tests, core tests, and server tests to use safely.
- [ ] #4 The documented fixture isolation model matches the implemented behavior.
- [ ] #5 Add focused tests or test helpers that prove two fixture copies can be opened independently without sharing the same destination path.
<!-- AC:END -->
