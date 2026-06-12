---
id: TASK-206
title: >-
  Migrator: Test the real migration implementation instead of duplicating it
  inline
status: Done
assignee: []
created_date: '2026-06-12 00:37'
updated_date: '2026-06-12 02:05'
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
- [x] #1 Migrator tests invoke the production migrate(src:context:) implementation or a shared testable module.
- [x] #2 Inline duplicate migration logic is removed from tests.
- [x] #3 Tests still cover empty DB and representative fixture DB migration behavior.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
This task was already completed by a prior commit (4d94f83 "TASK-099/107: Split migrator main.swift into 6 focused files"). All three acceptance criteria were already met:

1. MigratorTests.swift calls the production migrate(src:context:) at lines 164, 222, 269, 307, and 313.
2. No inline duplicate migration logic exists in the test file — schema setup helpers (createMinimalSchema, makeTempDB) are fixture helpers only, not migration logic.
3. Tests cover empty DB (testEmptyDBProducesZeroRows), fixture DB with jobs/captures/events/sites/resumes/settings (testFixtureDBRowCountsMatch), orphan skipping (testOrphanEventIsSkipped), and idempotency (testMigratorRefusesToRunOnNonEmptyStore).

Project.swift already includes tools/migrator/Migration.swift and tools/migrator/SQLiteHelpers.swift directly in CoreTests sources (lines 220-221), enabling the test target to call the production function without linking a command-line tool binary.

All 466 CoreTests pass.
<!-- SECTION:FINAL_SUMMARY:END -->
