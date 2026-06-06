---
id: TASK-023.09
title: 'M4: Implement  saved views in sidebar'
status: Done
assignee: []
created_date: '2026-05-27 18:06'
updated_date: '2026-05-31 04:41'
labels:
  - m4
  - web
  - ui-audit
  - navigation
dependencies:
  - TASK-023.01
modified_files:
  - src/jobhunt/static/shell.jsx
  - src/jobhunt/static/screens/jobs.jsx
  - src/jobhunt/static/main.jsx
  - src/jobhunt/api.py
  - src/jobhunt/db.py
  - tests/
parent_task_id: TASK-023
priority: medium
ordinal: 13000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Outstanding work: either remove sidebar saved views section or implement it end-to-end (clickable built-in views that apply live filters + optionally persisted custom views via /api/saved-views). Keep counts and state tied to actual filter behavior.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Clicking each built-in saved view navigates to Jobs and applies the matching filter state, or the saved view section is removed.
- [x] #2 Counts shown next to built-in saved views match the filter criteria used when clicked.
- [x] #3 `New view` either persists the current Jobs table state as a named saved view or is removed/disabled with clear unavailable affordance.
- [x] #4 If persisted saved views are implemented, they survive reloads and can be deleted or renamed.
- [x] #5 Saved view state composes cleanly with Jobs search, filters, sort, and column visibility.
- [x] #6 Tests or manual verification cover each built-in saved view click path.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Implemented in the Node app. Sidebar saved views apply built-in and custom Jobs filters, show live counts, support deleting custom views, survive reload via localStorage, and preserve the active saved view in the URL.
<!-- SECTION:FINAL_SUMMARY:END -->
