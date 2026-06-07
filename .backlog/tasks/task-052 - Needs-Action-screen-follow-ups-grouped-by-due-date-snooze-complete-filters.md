---
id: TASK-052
title: 'Needs Action screen: follow-ups grouped by due date, snooze/complete, filters'
status: To Do
assignee: []
created_date: '2026-06-07 22:49'
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
  - static/screens/needs.jsx
priority: medium
ordinal: 2900
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: Port the Needs Action task manager for job follow-ups.

## Read first
- swift-plan.md §10.2 #5 (Needs Action behavior).
- Legacy static/screens/needs.jsx (332 lines) — actions grouped Overdue/Today/Upcoming, filters (status + due state), search (company/title/note), batch snooze of overdue, per-action view-job/complete/snooze/edit-note.

## Implement (app/Views/Needs/)
- Read jobs with active actions via @Query; group by due bucket; filters + search; batch snooze overdue; per-row complete/snooze/edit via JobService action methods; view-job opens Detail.

## Dependencies
Depends on task-045 and task-046 (action complete/snooze, default snooze-days setting).

## Tests (AppUITests)
- Overdue/Today/Upcoming grouping correct; complete removes action; snooze moves bucket; filter + search work.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Actions grouped Overdue/Today/Upcoming with correct bucketing
- [ ] #2 Filters (status + due state) and search (company/title/note) work
- [ ] #3 Batch snooze of overdue + per-action complete/snooze/edit via JobService
- [ ] #4 View-job opens Detail; XCUITest covers complete/snooze/filter
<!-- AC:END -->
