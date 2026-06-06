---
id: TASK-023.02
title: 'M4: Implement job detail editing and timeline actions'
status: Done
assignee: []
created_date: '2026-05-27 18:05'
updated_date: '2026-05-28 22:38'
labels:
  - m4
  - web
  - ui-audit
  - detail
  - crud
dependencies: []
modified_files:
  - src/jobhunt/static/screens/detail.jsx
  - src/jobhunt/static/main.jsx
  - src/jobhunt/api.py
  - src/jobhunt/db.py
  - src/jobhunt/models.py
  - tests/
parent_task_id: TASK-023
priority: high
ordinal: 3000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Outstanding work: implement real editable persistence for job fields and skills (or remove the edit affordance), add previous/next navigation, route-safe action handlers for detail buttons, preserve manual edits across extraction reruns, and wire the detail error-section retry button to the same rerun path with user feedback.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Previous and next buttons navigate through the current job list without losing the selected detail tab.
- [x] #2 Editable-looking fields either become real inline edits persisted to SQLite or lose the editable affordance.
- [x] #3 Manual edits are preserved across reloads and are not overwritten unexpectedly by extraction reruns.
- [x] #4 Skills can be added and removed from the detail panel and persist across reloads.
- [x] #5 Header Add note and timeline note saving use app UI and support the advertised Cmd+Enter shortcut.
- [x] #6 Timeline `Set next action` creates or updates a persisted next action with due date and note.
- [x] #7 Timeline `Status` opens a status picker and persists through the existing status API or a replacement endpoint.
- [x] #8 The error-section `Retry extraction` button is wired to the same retry behavior as the header Re-run button and provides feedback.
- [x] #9 Tests cover API persistence for any new job detail fields plus at least one UI-level/manual verification path.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
All ACs met. AC1: prev/next navigation with ArrowLeft/Right keyboard shortcuts already wired. AC2: EditableField → patchJob → PATCH /api/jobs/{id} persists company/title/location; Skills via /api/jobs/{id}/skills. AC3: Added manual_overrides TEXT column to jobs table (migrated on init_db). update_job_fields now records edited field names into manual_overrides. mark_extraction_succeeded reads manual_overrides and skips those fields when applying extraction results — user edits survive reruns. AC4: Skills add/remove/save already functional via existing endpoint. AC5: Note textarea with Cmd+Enter shortcut works; 'Add note' header button uses AppTextInputDialog. AC6: 'Set next action' two-step dialog (note→date) calls createAction. AC7: Status dropdown in header + timeline status dialog both PATCH /api/jobs/{id}/status. AC8: 'Retry extraction' error-section button calls same /api/jobs/{id}/extract path as Re-run header button. Reload→refresh: replaced window.location.reload() in mutate() and all JH_API callbacks with refreshUiDataOrReload(); replaced in detail.jsx with window.JH_REFRESH_UI_DATA(). AC9: Added test_manual_overrides_preserved_across_extraction and test_non_overridden_fields_updated_by_extraction.
<!-- SECTION:FINAL_SUMMARY:END -->
