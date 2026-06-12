---
id: TASK-256
title: >-
  Persistence: Freeze SwiftData schema versions instead of mutating SchemaV1 in
  place
status: Done
assignee: []
created_date: '2026-06-12 02:50'
updated_date: '2026-06-12 03:09'
labels:
  - audit
  - persistence
  - swiftdata
  - migration
dependencies: []
references:
  - core/Models/Schema.swift
  - tests/CoreTests/SchemaEvolutionTests.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`SchemaV1.models` points directly at the live model classes and `JobhuntMigrationPlan` still has only V1 with no stages. If a stored property is renamed, removed, or type-changed, the persisted V1 shape changes in place instead of preserving an old schema snapshot for migration. Current schema evolution tests reopen the current schema, but do not prove migration from a real older store.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Breaking persisted model changes introduce a new `VersionedSchema` with a frozen old-shape snapshot and migration stage.
- [ ] #2 Schema evolution tests create or load an actual prior-version store and reopen it with the current migration plan.
- [ ] #3 The schema policy documents which changes require a new version and includes a checklist enforced by tests or review.
<!-- AC:END -->
