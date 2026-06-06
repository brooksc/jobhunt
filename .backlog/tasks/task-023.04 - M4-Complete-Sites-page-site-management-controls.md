---
id: TASK-023.04
title: 'M4: Complete Sites page site-management controls'
status: Done
assignee: []
created_date: '2026-05-27 18:05'
updated_date: '2026-05-31 04:41'
labels:
  - m4
  - web
  - ui-audit
  - sites
dependencies: []
modified_files:
  - src/jobhunt/static/screens/sites.jsx
  - src/jobhunt/static/app.jsx
  - src/jobhunt/static/main.jsx
  - src/jobhunt/api.py
  - src/jobhunt/db.py
  - src/jobhunt/models.py
  - tests/
parent_task_id: TASK-023
priority: medium
ordinal: 9000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Outstanding work: convert Sites page from multi-row review-log rendering to one current row per site, wire search and filter controls, implement real interval/reset-next-review actions, and make Add site a modal-backed CRUD operation rather than review-log-only append behavior.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Sites page displays one current row per site/origin rather than duplicate rows for every review event.
- [x] #2 Search filters by origin, page title, and note.
- [x] #3 Filter control supports Due, Never reviewed, All, and Reviewed recently states.
- [x] #4 Interval control either updates a site-specific default review interval or is removed until supported.
- [x] #5 `Reset due` performs a real action with confirmation or is replaced with a clearer supported command.
- [x] #6 `Add site` uses an app modal and persists a site record with origin, optional URL/title, interval, next review date, and note.
- [x] #7 Row mark-reviewed updates last/next review while preserving review history if history is retained.
- [x] #8 Row set-next-review and add-note update the current site state without creating duplicate current rows.
- [ ] #9 Tests cover site list derivation, add/update/review flows, and due-state metrics.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Implemented in the Node app. Sites are represented as current site rows with search/filter controls, Add site modal, update/review/note/interval/next-review actions, and site CRUD API support. Remaining test coverage is tracked separately under the testing backlog.
<!-- SECTION:FINAL_SUMMARY:END -->
