---
id: TASK-206
title: >-
  Migrator: Test the real migration implementation instead of duplicating it
  inline
status: To Do
assignee: []
created_date: '2026-06-12 00:37'
labels:
  - migration
  - tests
  - persistence
  - audit
dependencies: []
references:
  - Tests/CoreTests/MigratorTests.swift
  - tools/migrator/Migration.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Current migrator tests reimplement migration logic inside the test rather than exercising the production migrator. The test copy can drift from tools/migrator/Migration.swift and pass while the real migrator regresses.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Migrator tests invoke the production migrate(src:context:) implementation or a shared testable module.
- [ ] #2 Inline duplicate migration logic is removed from tests.
- [ ] #3 Tests still cover empty DB and representative fixture DB migration behavior.
<!-- AC:END -->
