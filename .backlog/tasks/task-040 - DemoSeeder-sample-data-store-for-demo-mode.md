---
id: TASK-040
title: 'DemoSeeder: sample-data store for demo mode'
status: Done
assignee:
  - claude
created_date: '2026-06-07 22:45'
updated_date: '2026-06-08 02:11'
labels:
  - swift-rewrite
  - core
milestone: m-1
dependencies:
  - TASK-034
documentation:
  - swift-plan.md
  - server/demo.js
  - server/demo.db
priority: low
ordinal: 1700
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: Port demo-data seeding so the app can show a populated UI with sample jobs/sites (used for screenshots, first-run exploration, and the demo banner toggle).

## Read first
- swift-plan.md §9 (DemoSeeder), §10.1 (demo banner in sidebar), §6.2 (use BackgroundStore actor).
- Legacy server/demo.js — ensureDemoDb/reseedDemoDb seed content and structure. The existing seeded SQLite is server/demo.db (inspect for realistic sample rows).

## Implement (core/Demo/DemoSeeder.swift)
- `seedDemo(into:)` and `reseedDemo(into:)` writing a representative set of jobs/captures/sites/resumes/events into a SEPARATE SwiftData store (a demo container distinct from the user store), via the BackgroundStore actor.
- A demo-mode switch the app uses to point the UI at the demo container vs the user container (replaces legacy /api/db/switch + /api/db/reseed-demo).

## Dependencies
Depends on task-034 (models). Uses task-035 BackgroundStore if available (otherwise its own context). Consumed by app shell (demo banner) and onboarding.

## Tests (CoreTests)
- seedDemo populates expected entity counts; reseedDemo resets cleanly; demo container is isolated from the user container.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 seedDemo writes representative jobs/sites/resumes/events into an isolated demo container
- [x] #2 reseedDemo resets demo data cleanly
- [x] #3 Demo vs user container switch works without touching user data
- [x] #4 CoreTests verify counts, reset, and isolation
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Implemented DemoSeeder.swift in core/Demo/ with:

- `DemoSeeder.seedDemo(into:)` — inserts 15 representative jobs (covering all statuses: offer, interview, applied, saved, rejected, archived), 3 sites, 2 resumes, with captures and events, into an isolated SwiftData container via BackgroundStore actor. Idempotent (no-op if jobs already exist).
- `DemoSeeder.reseedDemo(into:)` — deletes all entities (jobs, captures, sites, resumes, events, fit scores, LLM requests, etc.) then re-seeds from scratch.
- `ModelContainerFactory.demo()` — convenience async factory returning an in-memory container pre-seeded with demo data, separate from the user store.
- `DemoMode` enum (`.live` / `.demo`) for the app shell to switch between containers.

Jobs cover variety: different statuses/companies/salary ranges/remote modes, some with fit scores (58–91), some pending extraction, one duplicate, one non-job captured page.

17 CoreTests in Tests/CoreTests/DemoSeederTests.swift verify: exact entity counts (15 jobs, 3 sites, 2 resumes, 15 captures), status variety, fit score presence, pending extraction jobs, duplicate detection, idempotency, reseed cleanliness, and container isolation.

Build: clean (BUILD SUCCEEDED). Tests: 54 passing (0 failures), including all 17 new DemoSeeder tests.
<!-- SECTION:FINAL_SUMMARY:END -->
