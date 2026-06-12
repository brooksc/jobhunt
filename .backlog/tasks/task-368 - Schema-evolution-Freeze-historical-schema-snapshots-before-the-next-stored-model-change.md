---
id: TASK-368
title: >-
  Schema evolution: Freeze historical schema snapshots before the next stored
  model change
status: To Do
assignee: []
created_date: '2026-06-12 22:25'
labels:
  - audit
  - schema
  - migration
  - swiftdata
dependencies: []
references:
  - core/Models/Schema.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
SchemaV1 is documented as frozen, but SchemaV1.models points directly at the live model classes. Any stored-property change mutates the historical V1 shape instead of preserving a migration source snapshot.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Before the next stored model change, introduce immutable schema snapshot types or an equivalent historical schema strategy.
- [ ] #2 JobhuntMigrationPlan uses ordered historical snapshots rather than only live model classes when a new schema version is added.
- [ ] #3 Schema documentation and tests reflect the actual snapshot strategy.
<!-- AC:END -->
