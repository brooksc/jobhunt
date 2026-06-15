---
id: TASK-480
title: >-
  SchemaV2 readiness: snapshot V1 + golden old-store migration test (do at first
  breaking model change)
status: To Do
assignee: []
created_date: '2026-06-15 06:39'
labels:
  - schema
  - migration
  - swiftdata
  - deferred
dependencies: []
references:
  - core/Models/Schema.swift
  - tests/CoreTests/SchemaEvolutionTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Carries the future-conditional remainder of TASK-368/369, which can only be done when the first breaking stored-model change (SchemaV2) actually lands. Until then, V1 is protected by the compile-time name+type stability guards in SchemaEvolutionTests (see TASK-368/369 final summaries). When SchemaV2 is introduced: (1) snapshot the V1 models into a frozen namespace and make JobhuntMigrationPlan use ordered historical snapshots rather than the live model classes (TASK-368 AC#2); (2) add a golden file-backed old-store (V1) fixture + a SchemaV1→SchemaV2 migration test asserting old rows survive and new fields get expected defaults (TASK-369 AC#1/#2); (3) follow the "How to add a SchemaV2" steps documented in Schema.swift.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 V1 models snapshotted into a frozen namespace; JobhuntMigrationPlan uses ordered historical snapshots
- [ ] #2 Golden V1 old-store fixture committed and a V1→V2 migration test asserts data survives + new field defaults
- [ ] #3 Done as part of the first breaking schema change, not before
<!-- AC:END -->
