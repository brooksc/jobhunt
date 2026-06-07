---
id: TASK-050
title: >-
  Dashboard screen: top opportunities, pipeline funnel, activity chart, site
  schedule, quality summary
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
  - static/screens/dashboard.jsx
  - static/counts.js
priority: medium
ordinal: 2700
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: Port the Dashboard overview screen.

## Read first
- swift-plan.md §10.2 #1 (Dashboard sections).
- Legacy static/screens/dashboard.jsx (377 lines) — top opportunities (4 highest-fit), pipeline funnel (Saved→Applied→Interview→Offer, clickable to filter Jobs), 30-day daily activity bar chart, site check-in schedule, quality summary with action buttons, stat cards.
- static/counts.js (buildDailyActivity, activityTotal — port these).

## Implement (app/Views/Dashboard/)
- Read data via @Query; compute metrics with ported counts.js logic.
- Top-opportunity cards (open Detail on click), pipeline funnel (clicking a stage navigates to Jobs filtered by status via Router), daily activity using Swift Charts, site check-in list (upcoming/overdue), quality summary (counts + buttons that route to Data Quality / queue AI), stat cards.

## Dependencies
Depends on task-045 (shell/Router/components) and task-046 (data/metrics; for queue-AI buttons). Reads sites for the schedule.

## Tests (AppUITests + unit)
- Unit-test ported counts.js (buildDailyActivity/activityTotal) vs fixtures. XCUITest: funnel stage click navigates to filtered Jobs; top-opportunity card opens Detail.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Top opportunities, pipeline funnel, 30-day activity chart (Swift Charts), site schedule, quality summary, stat cards all present
- [ ] #2 Funnel stage click navigates to Jobs filtered by status; cards open Detail
- [ ] #3 Ported counts.js logic unit-tested against fixtures
- [ ] #4 XCUITest covers funnel navigation and card-open
<!-- AC:END -->
