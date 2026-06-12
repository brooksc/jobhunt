---
id: TASK-369
title: >-
  Schema tests: Add true old-store migration coverage for shipped schema
  versions
status: To Do
assignee: []
created_date: '2026-06-12 22:25'
labels:
  - audit
  - schema
  - tests
  - migration
dependencies: []
references:
  - tests/CoreTests/SchemaEvolutionTests.swift
  - core/Models/Schema.swift
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
- [ ] #3 Migration tests fail if a shipped stored property is renamed/removed without an appropriate migration stage.
<!-- AC:END -->
