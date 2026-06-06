---
id: TASK-013
title: Build local browser dashboard for tracked data
status: Done
assignee: []
created_date: '2026-05-27 05:19'
updated_date: '2026-05-27 05:29'
labels:
  - m4-export-workflow
  - dashboard
  - server
  - ui
dependencies:
  - TASK-007
  - TASK-012
modified_files:
  - src/jobhunt/api.py
  - src/jobhunt/dashboard.py
  - src/jobhunt/db.py
  - tests/test_dashboard.py
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Add a lightweight browser-accessible local dashboard served by the jobhunt server so the user can inspect captured jobs extracted fields statuses events and site review history without using sqlite3 directly. This is larger than the capture and extraction pipeline and should stay scoped to read/browse first unless explicitly expanded.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The local server exposes a browser page for viewing stored jobs and captures
- [x] #2 The page lists recent jobs with status extraction status company title source URL and captured date
- [x] #3 The page lists site reviews with site origin page title reviewed_at and next_review_at
- [x] #4 The implementation avoids adding a large frontend framework unless clearly justified
- [x] #5 Focused tests cover the data endpoints or rendering helpers that feed the dashboard
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Build a read-only server-rendered dashboard at `/` plus JSON data endpoints. Keep it framework-free: query SQLite in db helpers, render HTML in a small dashboard module, and test the data/query/render path through FastAPI TestClient.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented a read-only server-rendered dashboard at `/` and a JSON endpoint at `/api/dashboard`. It uses framework-free HTML rendering and SQLite read helpers. Smoke-tested against the user's real `.data/jobhunt.db` on port 8767; the endpoint returned the NVIDIA job and note event. The currently running server on 8765 must be restarted to pick up the new routes.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added a lightweight local browser dashboard. The server now exposes `/` for a read-only HTML dashboard and `/api/dashboard` for the backing data. The dashboard lists recent jobs with status extraction state source URL and captured date, recent events/notes, and site reviews. Tests cover the JSON data and rendered HTML paths.
<!-- SECTION:FINAL_SUMMARY:END -->
