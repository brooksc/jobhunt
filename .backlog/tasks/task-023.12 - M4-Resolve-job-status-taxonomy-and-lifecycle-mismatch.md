---
id: TASK-023.12
title: 'M4: Resolve job status taxonomy and lifecycle mismatch'
status: Done
assignee: []
created_date: '2026-05-27 18:10'
updated_date: '2026-05-28 22:34'
labels:
  - m4
  - web
  - ui-audit
  - workflow
dependencies: []
modified_files:
  - src/jobhunt/db.py
  - src/jobhunt/api.py
  - src/jobhunt/cli.py
  - src/jobhunt/static/main.jsx
  - src/jobhunt/static/components.jsx
  - src/jobhunt/static/screens/jobs.jsx
  - src/jobhunt/static/screens/detail.jsx
  - tests/
parent_task_id: TASK-023
priority: high
ordinal: 6000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Outstanding work: define a canonical status model, migrate UI/backend mappings so visible statuses round-trip unchanged, and reconcile deprecated statuses (`interested`, `closed`, `ignored`) with explicit user-facing semantics.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Backend and UI share one documented canonical status list for M4.
- [x] #2 Selecting any visible UI status persists and reloads as the same visible status.
- [x] #3 Screening is either a real persisted status or removed from all UI controls and filters.
- [x] #4 Archive/Closed/Ignored semantics are explicit and consistently represented in UI, API, and CLI.
- [x] #5 Metrics count statuses from the canonical model without alias drift.
- [x] #6 Tests cover round-tripping each visible status through PATCH `/api/jobs/{job_id}/status` and `/api/ui-data`.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Canonical status set is now: saved, applied, interview, offer, rejected, archived. All six names are used identically in DB storage, API, CLI, and UI — no mapping layer between them. Legacy names (interested→saved, interviewing→interview, closed/ignored→archived) are migrated on init_db via _migrate_legacy_statuses() and handled defensively in _db_status_to_ui() for any rows that predate the migration. Removed _ui_status_to_db() from api.py (was mapping interview→interviewing, archived→ignored). Removed _ui_to_db dict from cli.py. Fixed archive endpoint to use 'archived' instead of 'ignored'. Fixed duplicate resolution to use 'archived' instead of 'ignored'. Fixed _build_metrics key from 'interviewing' to 'interview'. Fixed main.jsx metrics key from 'interviewing' to 'interview'. Added parametrized round-trip test for all 6 statuses, legacy migration test, and invalid-status-rejected test. Added pytest import to test_api.py.
<!-- SECTION:FINAL_SUMMARY:END -->
