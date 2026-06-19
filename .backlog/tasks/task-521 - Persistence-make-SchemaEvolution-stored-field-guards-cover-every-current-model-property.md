---
id: TASK-521
title: >-
  Persistence: make SchemaEvolution stored-field guards cover every current
  model property
status: To Do
assignee: []
created_date: '2026-06-19 03:56'
labels:
  - audit
  - persistence
  - schema
  - tests
dependencies: []
references:
  - core/Models/Schema.swift
  - core/Models/Job.swift
  - tests/CoreTests/SchemaEvolutionTests.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: `SchemaEvolutionTests` documents V1 as frozen by compile-time name/type tripwires, but the name guard and full round-trip guard do not cover every current stored field. For example, `Job` has newer stored properties such as `salaryHourlyMin`, `salaryHourlyMax`, `manualFieldOverridesJSON`, and `meetsCriteria`; the type guard covers them, but the name guard and full job round-trip do not fully pin them. Similar gaps can appear when optional fields are added and only one guard is updated.

Why this matters: the project deliberately avoids a duplicated V1 snapshot until the first breaking SchemaV2 change. That policy only works if the tripwire tests accurately represent the live stored shape. Partial coverage lets a rename/removal or persistence regression slip through while the comments still claim V1 is protected.

Suggested implementation: audit all `@Model` stored properties in `core/Models` and update `SchemaEvolutionTests` so the name guard, type guard, and representative round-trip coverage agree with the current schema. Consider adding a small checklist/helper pattern that makes adding a new optional stored field require updating both guards in the same edit.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `testSchemaV1StoredPropertyNamesAreStable` reads every current stored property for every model registered in `SchemaV1.models`.
- [ ] #2 `testSchemaV1StoredPropertyTypesAreStable` remains in sync with the same stored-property set.
- [ ] #3 The full job round-trip regression test populates and verifies newer persisted job fields, including hourly salary fields, manual field overrides, and criteria match.
- [ ] #4 A future optional stored-property addition has an obvious test failure or checklist path that forces both schema guards to be updated.
- [ ] #5 Focused tests pass without introducing a SchemaV2 or changing production schema behavior.
<!-- AC:END -->
