---
id: TASK-120
title: 'Persistence: Define SwiftData schema evolution and migrator policy'
status: Done
assignee: []
created_date: '2026-06-11 02:47'
updated_date: '2026-06-11 03:30'
labels:
  - persistence
  - migration
  - swiftdata
  - architecture
dependencies: []
references:
  - core/Models/Schema.swift
  - tools/migrator
  - tests/CoreTests/MigratorTests.swift
  - Project.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`JobhuntMigrationPlan` currently contains only `SchemaV1` with no migration stages, while the standalone migrator has substantial patch and verify flows. Define the policy and test pattern for future SwiftData schema changes so model evolution does not depend on ad hoc migrator patches or manual verification.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A documented schema-evolution policy explains when to add a new `VersionedSchema` and migration stage
- [ ] #2 The standalone legacy migrator's supported role is clarified separately from in-app SwiftData schema migration
- [ ] #3 At least one migration test pattern exists for a future schema change, even if no production schema change is introduced in this task
- [ ] #4 Current `SchemaV1` behavior and existing migrator tests continue to pass
- [ ] #5 Untracked/split migrator files are reconciled into the intended project structure or explicitly documented as follow-up work
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added schema evolution policy documentation to Schema.swift covering when to create VersionedSchema, how to add SchemaV2, and the standalone migrator's role. Created SchemaEvolutionTests.swift with 5 tests: V1 round-trip, all model types insertable, migration plan structure invariants. Fixed compile error: Site init uses `origin:` not `name:`.
<!-- SECTION:FINAL_SUMMARY:END -->
