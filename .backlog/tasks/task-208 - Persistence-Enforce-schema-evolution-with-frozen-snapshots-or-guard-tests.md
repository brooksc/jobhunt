---
id: TASK-208
title: 'Persistence: Enforce schema evolution with frozen snapshots or guard tests'
status: To Do
assignee: []
created_date: '2026-06-12 00:37'
labels:
  - persistence
  - swiftdata
  - migration
  - audit
dependencies: []
references:
  - core/Models/Schema.swift
  - Tests/CoreTests/SchemaEvolutionTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
SchemaV1.models points at live model classes. The policy comments require a new VersionedSchema for incompatible changes, but there is no enforcement that prevents accidental mutation of the historical schema.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A guard test or tooling detects stored model changes that require a new schema version.
- [ ] #2 Future schema versions have frozen model snapshots or an equivalent SwiftData-safe approach.
- [ ] #3 Schema evolution documentation is updated to match the enforced workflow.
<!-- AC:END -->
