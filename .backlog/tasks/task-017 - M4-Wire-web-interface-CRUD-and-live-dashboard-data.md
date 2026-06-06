---
id: TASK-017
title: 'M4: Wire web interface CRUD and live dashboard data'
status: Done
assignee:
  - Codex
created_date: '2026-05-27 06:42'
updated_date: '2026-05-27 06:50'
labels:
  - m4
  - web
  - crud
dependencies: []
modified_files:
  - src/jobhunt/api.py
  - src/jobhunt/db.py
  - src/jobhunt/models.py
  - src/jobhunt/static/index.html
  - src/jobhunt/static/main.jsx
  - src/jobhunt/static/app.jsx
  - src/jobhunt/static/shell.jsx
  - src/jobhunt/static/components.jsx
  - src/jobhunt/static/screens/detail.jsx
  - src/jobhunt/static/screens/jobs.jsx
  - src/jobhunt/static/screens/sites.jsx
  - src/jobhunt/static/screens/duplicates.jsx
  - src/jobhunt/static/screens/dashboard.jsx
  - src/jobhunt/static/screens/settings.jsx
  - src/jobhunt/static/screens/needs.jsx
  - src/jobhunt/static/vendor/react.development.js
  - src/jobhunt/static/vendor/react-dom.development.js
  - src/jobhunt/static/vendor/babel.min.js
  - tests/test_api.py
  - tests/test_dashboard.py
  - pyproject.toml
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Turn the new AI-designed web interface into the functional M4 application. The UI should use real API-backed data and avoid misleading mock-only controls for job management, notes, site review tracking, duplicate decisions, theme handling, and dashboard counts.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Existing backend tests pass after the React dashboard replaces the server-rendered root page behavior.
- [x] #2 The web UI loads live jobs, sites, duplicates, metrics, hashes, and cleaned/raw description data from the local API without static mock counts for core navigation/status indicators.
- [x] #3 Users can update job status, add notes, archive jobs, rerun extraction, and open source URLs from the web UI with persisted results.
- [x] #4 Users can update site review records from the web UI with persisted reviewed dates and notes.
- [x] #5 Users can mark duplicate groups as merged or not duplicate from the web UI with persisted event/status changes.
- [x] #6 Dark/light theme selection supports auto mode and persists across reloads.
- [x] #7 The local UI does not depend on remote CDN assets for React/Babel/fonts at runtime, or the remaining dependency is explicitly documented as temporary for M4.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Inspect current database APIs and schema to reuse existing helpers where possible.
2. Add focused FastAPI endpoints for UI actions: update job status, add job note, archive job, rerun extraction, update site review, and duplicate decisions.
3. Expand /api/ui-data so the React UI receives live metrics, hashes, cleaned description, raw metadata, and non-mock counts.
4. Wire React screens to refresh data after persisted mutations and remove or disable misleading no-op controls.
5. Fix date/theme behavior: dynamic current dates, persisted dark/light/auto theme.
6. Remove runtime CDN dependency where practical for M4 by serving installed local React assets or document any temporary remaining dependency.
7. Update tests for the new static root page and add API tests for the new CRUD endpoints, then run the focused suite.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented M4 wiring as an API-backed version of the existing AI-designed UI. Mutation handlers refresh the local dataset after persisted changes; this keeps the no-build React prototype simple while making visible controls honest. Rerun extraction queues the job by resetting extraction_status to pending; the existing extraction CLI remains the worker that processes pending rows. Duplicate decisions are persisted in a new duplicate_decisions table so resolved groups disappear from the UI.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Implemented the M4 web interface wiring. Added API endpoints for job status updates, notes, archiving, extraction requeue, duplicate decisions, site-review updates, and CSV export. Expanded /api/ui-data with live metrics, cleaned/raw description metadata, hashes, byte sizes, events, sites, and settings. Wired the React UI actions to those endpoints, removed hard-coded dates/counts/mock values from core navigation and settings, added persisted dark/light/auto theme mode, and served React/Babel locally from static/vendor instead of remote CDNs. Updated tests for the static app shell, live UI data, and the new mutation endpoints.

Verification: .venv/bin/python -m pytest -> 33 passed; .venv/bin/python -m compileall src/jobhunt -> passed; TestClient smoke checked /, /static/vendor/react.development.js, /api/ui-data, and /exports/jobs.csv.
<!-- SECTION:FINAL_SUMMARY:END -->
