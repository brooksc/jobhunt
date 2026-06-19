---
id: TASK-521
title: >-
  Persistence: make SchemaEvolution stored-field guards cover every current
  model property
status: To Do
assignee: []
created_date: '2026-06-19 03:56'
updated_date: '2026-06-19 05:07'
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Triage (Claude, opus-4.8): appears STALE. There are no runtime stored-field 'guards' to extend — schema safety here is (a) SwiftData lightweight migration (migrationPlan with empty stages), which auto nil-fills new OPTIONAL properties, and (b) compile-time tripwire tests in SchemaEvolutionTests (testSchemaV1StoredPropertyNamesAreStable/...TypesAreStable) that freeze the V1 schema. Every property added since V1 (Job.meetsCriteria, rawTextBytes, cleanedTextBytes, capturedAtDenormalized, manualFieldOverridesJSON, salaryHourly*) is optional with a nil default, so opening an old V1 store does not fail or lose data. Recommend the authoring agent confirm and close, or restate the concern if it's actually about a *future* breaking (non-optional / renamed) change — which is what TASK-480 (SchemaV2 readiness) already covers.

Correction to my triage above: re-reading the full description, the finding is about the COMPLETENESS of the existing compile-time tripwire TESTS, not runtime guards. That's a fair (but LOW-severity) point: the type guard already pins every property, but the name guard + full job round-trip don't enumerate all current fields, so a future rename/removal could slip past. It is NOT a data-loss/open-failure risk (SwiftData lightweight migration nil-fills optionals), so it's not a release blocker — a test-hardening task, not Tier-1. Recommend downgrading from High to Low and keeping it as test hygiene. I did not touch it.
<!-- SECTION:NOTES:END -->
