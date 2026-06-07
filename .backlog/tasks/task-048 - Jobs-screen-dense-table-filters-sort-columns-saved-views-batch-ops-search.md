---
id: TASK-048
title: >-
  Jobs screen: dense table, filters, sort, columns, saved views, batch ops,
  search
status: To Do
assignee: []
created_date: '2026-06-07 22:48'
labels:
  - swift-rewrite
  - ui
  - screen
milestone: m-1
dependencies:
  - TASK-045
  - TASK-046
documentation:
  - swift-plan.md
  - static/screens/jobs.jsx
  - static/sort.js
  - static/counts.js
  - static/transform.js
priority: high
ordinal: 2500
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: Port the most complex screen — the dense, filterable, sortable jobs table with configurable columns, saved views, batch selection/operations, and search. This is the app's primary surface.

## Read first
- swift-plan.md §10.2 #2 (Jobs screen full feature list), §10.3 (table perf note: SwiftUI Table; drop to NSTableView only if profiling demands), §10.1 (Router/saved views), §10.4 (components).
- Legacy static/screens/jobs.jsx (1196 lines) — the authority: 18 configurable columns, 16 sort keys, fixed + dynamic filters, saved views (predefined + custom), batch ops (status/queue-AI/open-sources/compare), search incl #number mode, ⌘K focus, row→detail selection.
- static/sort.js (sortValue/sortJobs), static/counts.js, static/transform.js (display mapping). Port sort.js logic exactly.

## Implement (app/Views/Jobs/)
- SwiftUI `Table` (or NSTableView-backed if needed) reading jobs via @Query; selectable columns (18), default set per legacy; column visibility control.
- Sorting by the 16 keys via ported sort.js semantics (empty-to-bottom, numeric vs locale string, salary/fit/date/next-action special cases).
- Fixed filters (status, meets-criteria/remote, rating, extraction, source, duplicates, salary) + dynamic facet filters derived from data (work mode, employment, seniority, company, location, salary band, fit, next-action).
- Saved views: predefined (status:*, active applications, meets criteria, this week's captures) + user-created (save current filter/sort; delete) persisted via the Router/SettingsStore; reflected in sidebar (task-045).
- Batch selection (click + shift-click range) + bulk actions calling JobService (set status, queue AI, open source URLs, compare side-by-side).
- Search box (company/title/location; #N job-number mode); ⌘K focuses search. Row selection opens the Detail inspector (task T) and marks opened/read.

## Dependencies
Depends on task-045 (shell/components/Router) and task-046 (JobService bulk ops). Pairs with task T (Detail inspector fills the third column).

## Tests (AppUITests + unit)
- Unit-test the ported sort + filter logic against fixtures (parity with sort.js / jobs.jsx behavior). XCUITest: filter, sort, multi-select + bulk status change, save/apply a view, ⌘K search, row→detail.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Table with 18 configurable columns + default set; column visibility control
- [ ] #2 Sorting reproduces sort.js semantics across all 16 keys
- [ ] #3 Fixed + dynamic filters reproduce jobs.jsx behavior; meets-criteria logic correct
- [ ] #4 Saved views (predefined + custom save/delete) persist and reflect in sidebar
- [ ] #5 Batch select (shift-click range) + bulk ops (status/queue-AI/open-sources/compare) via JobService
- [ ] #6 Search incl #N mode + ⌘K focus; row selection opens Detail and marks opened/read
- [ ] #7 Unit tests for sort/filter parity; XCUITest covers filter/sort/bulk/saved-view/search
<!-- AC:END -->
