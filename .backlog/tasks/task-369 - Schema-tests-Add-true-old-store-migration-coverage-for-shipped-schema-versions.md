---
id: TASK-369
title: >-
  Schema tests: Add true old-store migration coverage for shipped schema
  versions
status: To Do
assignee: []
created_date: '2026-06-12 22:25'
updated_date: '2026-06-15 04:10'
labels:
  - audit
  - schema
  - tests
  - migration
dependencies: []
references:
  - tests/CoreTests/SchemaEvolutionTests.swift
  - core/Models/Schema.swift
modified_files:
  - tests/CoreTests/SchemaEvolutionTests.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
SchemaEvolutionTests currently write with the current schema and reopen with the same current schema. That catches some regressions but does not prove old shipped stores migrate to new schema versions.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Add golden file-backed old-store fixtures or explicit SchemaV1Snapshot-to-new-schema migration tests when V2 lands.
- [ ] #2 Tests assert old rows survive and new fields receive expected defaults or migrated values.
- [x] #3 Migration tests fail if a shipped stored property is renamed/removed without an appropriate migration stage.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
AC#3 satisfied and extended: added testSchemaV1StoredPropertyTypesAreStable, which fails to compile if any storage-critical stored property is renamed, removed, OR retyped without a migration stage (the existing name-only guard missed type changes). 

REMAINING (AC#1, AC#2): a true old-store migration test still needs either (a) a committed golden file-backed V1 store fixture, or (b) an explicit SchemaV1Snapshot→SchemaV2 migration test — both depend on work deferred to when V2 lands (and the golden-binary-fixture path also intersects the open fixture-policy tasks TASK-417/422). Deliberately deferred. Note: the current same-process round-trip tests can't catch type drift because they write and read with the same live models — the compile-time type guard is the now-available substitute until a frozen on-disk fixture exists.
<!-- SECTION:NOTES:END -->
