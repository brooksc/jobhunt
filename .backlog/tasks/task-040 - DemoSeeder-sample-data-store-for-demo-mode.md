---
id: TASK-040
title: 'DemoSeeder: sample-data store for demo mode'
status: In Progress
assignee:
  - claude
created_date: '2026-06-07 22:45'
updated_date: '2026-06-08 02:05'
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
- [ ] #1 seedDemo writes representative jobs/sites/resumes/events into an isolated demo container
- [ ] #2 reseedDemo resets demo data cleanly
- [ ] #3 Demo vs user container switch works without touching user data
- [ ] #4 CoreTests verify counts, reset, and isolation
<!-- AC:END -->
