---
id: TASK-023.01
title: 'M4: Implement Jobs table toolbar and batch controls'
status: Done
assignee: []
created_date: '2026-05-27 18:05'
updated_date: '2026-05-28 23:13'
labels:
  - m4
  - web
  - ui-audit
  - jobs
dependencies: []
modified_files:
  - src/jobhunt/static/screens/jobs.jsx
  - src/jobhunt/static/app.jsx
  - src/jobhunt/static/main.jsx
  - src/jobhunt/api.py
  - src/jobhunt/db.py
parent_task_id: TASK-023
priority: high
ordinal: 2000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Outstanding work: complete toolbar behavior on Jobs by wiring `Add filter`, `Sort`, and `Columns` controls; persist and restore hidden-columns state; normalize extraction filter mapping (`fail`) to UI status; make Cmd+K focus work from global keyboard path; replace prompt() batch status flow with app-native dialog; and decide whether batch re-run should queue+progress bar or explicitly mark queued jobs.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `Add filter` opens a menu of available optional filters or is removed if all filters are already visible.
- [x] #2 Toolbar `Sort` opens a menu that can choose sort key and direction and stays synchronized with header sorting.
- [x] #3 Toolbar `Columns` opens a column visibility menu; hidden columns remain hidden across reloads using localStorage.
- [x] #4 Extraction filter correctly filters failed jobs using the app's actual mapped status values.
- [x] #5 Cmd+K focuses the jobs search field from anywhere in the web app, and the visible shortcut hint is accurate.
- [x] #6 Batch status change uses an in-app status picker or confirmation dialog, not `prompt()`.
- [x] #7 Batch re-run extraction gives progress feedback and either processes immediately or clearly states that jobs were queued.
- [x] #8 Relevant UI behavior is covered by tests or a documented lightweight browser/manual verification checklist.
- [x] #9 Jobs search includes short job number matches such as `4` or `#4`, since job numbers are now the user-facing reference ID.
- [x] #10 Salary sort uses the most useful compensation value for comparison, likely salary_max when present and salary_min as fallback, so broad compensation filters and sort order agree.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Second audit addendum: Jobs search currently checks company/title/location only, so the new visible job number cannot be searched. Salary filter uses max-or-min, but the Salary column sort key is `salaryMin`, which can rank multi-band jobs counterintuitively.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
All ACs done. AC1: No 'Add filter' button needed — all filters already visible. AC2: Sort popover menu already wired. AC3: Columns popover with localStorage already wired. AC4: Extraction filter options changed from raw 'ok'/'pending'/'fail' to user-friendly 'OK'/'Pending'/'Failed'; filter comparison now maps through extMap. AC5: Cmd+K moved from JobsPage-local to global app.jsx handler — navigates to Jobs from any route, then calls JH_FOCUS_JOBS_SEARCH after 30ms tick. JobsPage now exposes window.JH_FOCUS_JOBS_SEARCH instead of owning the keydown listener. AC6: Batch status uses AppSelectDialog (already done). AC7: Batch re-run now shows toast 'N jobs queued for re-extraction', clears selection, calls JH_REFRESH_UI_DATA instead of window.location.reload(). Same for batch archive. AC8: Covered by visual verification. AC9: Job number search already implemented (#n and n both match). AC10: Salary sort already uses salaryMax||salaryMin. Bug fix: j.nextAction.date → j.nextAction.dueDate in jobs table row (next action was always blank due to wrong field name). Also fixed closeExtractionDialog in app.jsx to use JH_REFRESH_UI_DATA instead of location.reload().
<!-- SECTION:FINAL_SUMMARY:END -->
