---
id: TASK-421
title: 'Fixture seeding: Make generated test data deterministic'
status: To Do
assignee: []
created_date: '2026-06-13 04:21'
labels:
  - audit
  - fixtures
  - determinism
dependencies: []
references:
  - core/Demo/FixtureSeeder.swift
  - docs/test-db-spec.md
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The test DB spec describes deterministic fixture data, but `FixtureSeeder` uses `Date()` and `Date(timeIntervalSinceNow:)` while constructing records. Regenerating the fixture can therefore produce different SQLite contents and manifests even when the logical dataset has not changed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Fixture seeding uses a fixed clock or explicit base date so regenerated test fixtures are stable across runs.
- [ ] #2 Any relative dates in the fixture are derived from the fixed base date, not wall-clock time.
- [ ] #3 Documentation accurately describes the timestamp policy used by fixture data.
- [ ] #4 Add verification that regenerating the fixture twice from the same source inputs yields equivalent logical data or a stable manifest.
<!-- AC:END -->
