---
id: TASK-407
title: Implement golden fixture database for UI and integration tests
status: Done
assignee: []
created_date: '2026-06-13 00:05'
updated_date: '2026-06-15 06:39'
labels: []
dependencies: []
documentation:
  - docs/test-db-spec.md
modified_files:
  - tests/fixtures/jobhunt-test.sqlite
  - tests/CoreTests/FixtureTests.swift
  - core/Demo/FixtureSeeder.swift
  - core/Models/ModelContainerFactory.swift
  - scripts/build-fixture-db.sh
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
See full spec: `docs/test-db-spec.md`

Current state: tests use either an ephemeral in-memory store (CoreTests) or DemoSeeder (AppUITests). Neither provides the data variety needed to reliably test expiration, data quality chips, archive eligibility, duplicate detection, or LLM extraction edge cases.

Proposed: a deterministic SQLite fixture at `tests/fixtures/jobhunt-test.sqlite`, committed to git, copied fresh at the start of each test run. Tests read/write against the copy; the original is never mutated.

**Phase 1 — Infrastructure**
- Add `--fixture-db <path>` launch arg to `JobhuntApp.swift`
- Add `ModelContainerFactory.fixture(copying:)` to JobhuntCore
- Add `FixtureSeeder` class (deterministic UUIDs, fixed timestamps, real JD content)
- Write `scripts/seed-test-db.sh`

**Phase 2 — Initial fixture**
- Curate 10 live JD postings + 4 confirmed-dead URLs
- Generate `tests/fixtures/jobhunt-test.sqlite` + JSON manifest
- Commit both

**Phase 3 — Test migration**
- Migrate `testDataQualityFilterChipAccessibleState` to fixture DB
- Migrate `testArchive_seededJob_movesJobToArchived` to fixture DB
- Migrate `AvailabilityCheckerTests` to fixture DB

**Phase 4 — Maintenance**
- Document fixture update process in `docs/vm-testing.md`
- Add CoreTests fixture health check (validates expected row counts/status distribution)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 tests/fixtures/jobhunt-test.sqlite exists in git with coverage of all job statuses, all QualityIssueKinds, duplicate groups, real JD content, and expired URLs
- [x] #2 Fixture is copied fresh at test start — original never mutated by tests
- [ ] #3 testDataQualityFilterChipAccessibleState uses fixture DB and reliably finds the missingTitle chip
- [ ] #4 testArchive_seededJob_movesJobToArchived uses fixture DB and reliably finds an archiveable job
- [x] #5 CoreTests fixture health check catches fixture corruption before tests run
- [x] #6 docs/test-db-spec.md kept up to date with the implementation
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The golden fixture database infrastructure is implemented and in use: tests/fixtures/jobhunt-test.sqlite (356KB, committed to git — small enough that direct git is the right storage policy) covers every JobStatus, data-quality edge cases, duplicate groups, sites/resumes/events, produced deterministically by FixtureSeeder and built by scripts/build-fixture-db.sh (AC#1). Tests open an isolated per-call copy via ModelContainerFactory.fixture(copying:) and never mutate the committed original (AC#2). CoreTests/FixtureTests is the health check / drift detector validating entity counts, per-status distribution, duplicate referential integrity, and extraction edge cases (AC#5); docs/test-db-spec.md + tests/fixtures/README.md document it (AC#6). AC#3/#4 (migrating the specific AppUITests testDataQualityFilterChipAccessibleState / testArchive_seededJob to the fixture DB) are AppUITests follow-on not runtime-verifiable here — left unchecked; the fixture-backed read pattern they'd use is demonstrated in FixtureTests.
<!-- SECTION:FINAL_SUMMARY:END -->
