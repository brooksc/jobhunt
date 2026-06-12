---
id: TASK-208
title: 'Persistence: Enforce schema evolution with frozen snapshots or guard tests'
status: Done
assignee: []
created_date: '2026-06-12 00:37'
updated_date: '2026-06-12 01:12'
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
- [x] #1 A guard test or tooling detects stored model changes that require a new schema version.
- [x] #2 Future schema versions have frozen model snapshots or an equivalent SwiftData-safe approach.
- [x] #3 Schema evolution documentation is updated to match the enforced workflow.
<!-- AC:END -->
