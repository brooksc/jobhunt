---
id: TASK-053
title: 'Sites screen: site list + detail inspector, review state machine, scheduling'
status: Done
assignee: []
created_date: '2026-06-07 22:49'
updated_date: '2026-06-08 03:31'
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
  - static/screens/sites.jsx
priority: medium
ordinal: 3000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: Port the Sites (job-board prospecting) screen.

## Read first
- swift-plan.md §10.2 #6 (Sites behavior), §9 (SiteService).
- Legacy static/screens/sites.jsx (547 lines) — site table (URL, company, last/next review, state), detail inspector (editable fields, review-state selector not_reviewed/reviewed/exclude, interval + next-review auto-calc, mark-reviewed, visit jobs URL, delete), add-site dialog, state machine + overdue surfacing.

## Implement (app/Views/Sites/)
- Site list via @Query; detail inspector in the third column; add-site flow; mark-reviewed (records last/next via SiteService); state transitions; interval editing; open jobs URL externally; delete.

## Dependencies
Depends on task-045 (shell/inspector) and task-046 (SiteService).

## Tests (AppUITests)
- Add a site; edit fields; mark reviewed (moves section, sets next-review); change state to exclude (hidden from review); delete.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Site list + detail inspector with all editable fields
- [ ] #2 Review state machine (not_reviewed/reviewed/exclude) + interval + next-review auto-calc via SiteService
- [ ] #3 Add-site flow, mark-reviewed, visit jobs URL, delete
- [ ] #4 XCUITest covers add/edit/review/exclude/delete
<!-- AC:END -->
