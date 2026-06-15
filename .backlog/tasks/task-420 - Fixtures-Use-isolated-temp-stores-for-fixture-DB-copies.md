---
id: TASK-420
title: 'Fixtures: Use isolated temp stores for fixture DB copies'
status: Done
assignee: []
created_date: '2026-06-13 04:21'
updated_date: '2026-06-15 06:38'
labels:
  - audit
  - fixtures
  - tests
dependencies: []
references:
  - core/Models/ModelContainerFactory.swift
  - docs/test-db-spec.md
modified_files:
  - core/Models/ModelContainerFactory.swift
  - tests/CoreTests/FixtureTests.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`ModelContainerFactory.fixture(copying:)` copies every fixture source into a fixed temp path under `NSTemporaryDirectory()/JobhuntFixture/jobhunt-fixture.store`, deleting any prior store first. This makes parallel test runs and simultaneous local launches race with each other, and it does not satisfy the test DB spec's per-class/per-run isolation goal.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Fixture DB copies use a unique destination per test run, process, or caller-provided isolation scope instead of one global temp file.
- [x] #2 Parallel fixture consumers cannot delete or overwrite each other's temp stores.
- [x] #3 The fixture API makes ownership and cleanup expectations explicit enough for UI tests, core tests, and server tests to use safely.
- [x] #4 The documented fixture isolation model matches the implemented behavior.
- [x] #5 Add focused tests or test helpers that prove two fixture copies can be opened independently without sharing the same destination path.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ModelContainerFactory.fixture(copying:) now copies into a unique per-call directory (NSTemporaryDirectory/JobhuntFixture/<UUID>/jobhunt-fixture.store) instead of one shared global path that was deleted on each call (AC#1) — parallel consumers/launches can no longer race or delete each other's store (AC#2). The doc comment states ownership/cleanup expectations (caller owns the container; temp copy left for the OS to reclaim) (AC#3/#4). testFixtureCopiesAreIsolatedPerCall opens two copies and asserts distinct destination paths (AC#5).
<!-- SECTION:FINAL_SUMMARY:END -->
