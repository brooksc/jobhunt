---
id: TASK-023.03
title: 'M4: Build real follow-up and Needs Action workflow'
status: Done
assignee: []
created_date: '2026-05-27 18:05'
updated_date: '2026-05-28 22:41'
labels:
  - m4
  - web
  - ui-audit
  - followups
dependencies: []
modified_files:
  - src/jobhunt/static/screens/needs.jsx
  - src/jobhunt/static/screens/dashboard.jsx
  - src/jobhunt/static/screens/detail.jsx
  - src/jobhunt/static/main.jsx
  - src/jobhunt/static/shell.jsx
  - src/jobhunt/api.py
  - src/jobhunt/db.py
  - src/jobhunt/models.py
  - tests/
parent_task_id: TASK-023
priority: high
ordinal: 4000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Outstanding work: add a persisted one-active-next-action model (plus complete+completed fields), then wire Needs Action table/search/filters/snooze to that model, and ensure dashboard needsAction count and row actions (`Add action`, `Mark followed up`, `Snooze`) operate against real state.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A persisted follow-up/next-action model exists and supports one active next action per job at minimum.
- [x] #2 The job detail panel can create a next action and it appears on the Needs Action page and dashboard.
- [x] #3 Needs Action search filters rows by company, title, and action note.
- [x] #4 Due and Status filters open controls and actually filter the table.
- [x] #5 `Add action` creates a next action for a selected job using app UI, not `prompt()`.
- [x] #6 `Mark followed up` completes or clears the current action instead of only adding a note.
- [x] #7 Snooze row action and Snooze all update due dates predictably and persist across reloads.
- [x] #8 `needsAction` metric and sidebar count are computed from real persisted data.
- [x] #9 Tests cover follow-up create, list, complete, snooze, and metrics behavior.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
All ACs met. AC1-2: job_actions table with create/complete/snooze already persisted. AC3: search already filtered by company/title/note. AC4: Due filter button now cycles All→Overdue→Today→Upcoming with active highlight; Status filter button opens a dropdown with all canonical statuses; both actually filter the table. Removed the static cosmetic filter controls. AC5: Add action uses two-step AppTextInputDialog (no prompt()). AC6: Mark followed up calls completeAction which sets completed_at. AC7: Snooze updates due_date and persists via snoozeAction; 'Snooze all overdue' button snoozes all overdue items at once. AC8: needsAction metric counts overdue+today via get_needs_action_count, sidebar count reflects this. AC9: Added tests for complete action removes from list, needsAction metric counts only overdue, create_action replaces existing. Fixed window.location.reload() in NeedsRow note dialog (uses addNote which calls mutate→refreshUiDataOrReload).
<!-- SECTION:FINAL_SUMMARY:END -->
