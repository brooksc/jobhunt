---
id: TASK-180
title: 'Settings: Enforce uniqueness and validation for persisted setting keys'
status: To Do
assignee: []
created_date: '2026-06-11 22:14'
labels:
  - audit
  - settings
  - data-integrity
dependencies: []
references:
  - core/Models/Setting.swift
  - core/Settings/SettingsStore.swift
  - tests/CoreTests/SettingsStoreTests.swift
  - tests/CoreTests/MigratorTests.swift
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`Setting.key` is a plain string with no uniqueness constraint, and `SettingsStore.persistToStore` updates only the first matching row. Duplicate or unknown setting rows can create ambiguous behavior and make migrations harder. Add uniqueness/validation at the model or service boundary and add cleanup logic for existing duplicates if needed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Persisted settings cannot accumulate duplicate keys through normal SettingsStore writes.
- [ ] #2 Unknown or unsupported keys are either rejected, namespaced, or explicitly allowed by policy.
- [ ] #3 Tests cover duplicate-key handling and migration/cleanup behavior for pre-existing duplicate rows.
<!-- AC:END -->
