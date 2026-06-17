---
id: TASK-421
title: 'Fixture seeding: Make generated test data deterministic'
status: Done
assignee: []
created_date: '2026-06-13 04:21'
updated_date: '2026-06-17 04:45'
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
- [x] #1 Fixture seeding uses a fixed clock or explicit base date so regenerated test fixtures are stable across runs.
- [x] #2 Any relative dates in the fixture are derived from the fixed base date, not wall-clock time.
- [x] #3 Documentation accurately describes the timestamp policy used by fixture data.
- [x] #4 Add verification that regenerating the fixture twice from the same source inputs yields equivalent logical data or a stable manifest.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
FixtureSeeder now derives every timestamp from a single FIXED base instant (`Date(timeIntervalSince1970: 1_750_000_000)` = 2025-06-15T07:46:40Z) via `daysAgo`/`daysFromNow` — previously `now` was `Date()` and the day-offset helpers used wall-clock `Date(timeIntervalSinceNow:)`, so regenerating the fixture drifted (AC#1/#2). The only `Date()` in the file was that base; all model dates (Capture/Job createdAt/capturedAt, events, actions, sites, searches) already flow from it. AC#3: documented the timestamp policy in docs/test-db-spec.md. AC#4: FixtureTests.testFixtureSeed_isDeterministicAcrossRuns seeds two in-memory stores and asserts identical createdAt/capturedAt per job, anchored below a wall-clock-independent ceiling. 818 CoreTests green. One-time follow-up for the maintainer: re-run scripts/build-fixture-db.sh to regenerate the committed jobhunt-test.sqlite to the deterministic baseline (it's still structurally valid now — counts unchanged — just built with the old wall-clock dates).
<!-- SECTION:FINAL_SUMMARY:END -->
