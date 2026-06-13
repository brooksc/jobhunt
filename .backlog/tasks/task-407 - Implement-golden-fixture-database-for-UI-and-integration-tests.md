---
id: TASK-407
title: Implement golden fixture database for UI and integration tests
status: To Do
assignee: []
created_date: '2026-06-13 00:05'
labels: []
dependencies: []
documentation:
  - docs/test-db-spec.md
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
- [ ] #1 tests/fixtures/jobhunt-test.sqlite exists in git with coverage of all job statuses, all QualityIssueKinds, duplicate groups, real JD content, and expired URLs
- [ ] #2 Fixture is copied fresh at test start — original never mutated by tests
- [ ] #3 testDataQualityFilterChipAccessibleState uses fixture DB and reliably finds the missingTitle chip
- [ ] #4 testArchive_seededJob_movesJobToArchived uses fixture DB and reliably finds an archiveable job
- [ ] #5 CoreTests fixture health check catches fixture corruption before tests run
- [ ] #6 docs/test-db-spec.md kept up to date with the implementation
<!-- AC:END -->
