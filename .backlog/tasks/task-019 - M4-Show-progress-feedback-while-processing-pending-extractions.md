---
id: TASK-019
title: 'M4: Show progress feedback while processing pending extractions'
status: Done
assignee:
  - Codex
created_date: '2026-05-27 07:37'
updated_date: '2026-05-27 07:39'
labels:
  - m4
  - web
  - ux
  - extraction
dependencies: []
modified_files:
  - src/jobhunt/static/app.jsx
  - src/jobhunt/static/main.jsx
  - src/jobhunt/static/screens/dashboard.jsx
  - src/jobhunt/static/styles.css
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
When the user processes pending extractions from the web interface, show visible feedback, prevent repeated clicks while the request is running, and report the processed/succeeded/failed result when the request completes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Clicking Process pending opens a blocking progress dialog or equivalent visible progress state.
- [x] #2 Process pending controls are disabled while extraction processing is in flight so repeated clicks cannot start duplicate requests.
- [x] #3 The UI displays pending progress context such as the number of outstanding jobs before processing and the final processed succeeded and failed counts after completion.
- [x] #4 The dialog handles errors clearly and leaves the user able to retry.
- [x] #5 Automated tests still pass after the UI/API changes.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Update the client API helper so extraction processing returns summary data instead of immediately reloading.
2. Add top-level extraction processing state in JobhuntApp and pass an action handler to route actions and dashboard cards.
3. Add a modal/progress dialog showing queued count, in-flight state, final counts, and error state with retry/close controls.
4. Disable all Process pending buttons while processing is in flight.
5. Add minimal CSS for the modal/progress bar using existing design tokens.
6. Run the Python test suite and a static search for stale direct processExtractions calls.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented progress feedback client-side around the existing synchronous extraction endpoint. The dialog shows queued count while the request is running and final processed/succeeded/failed counts when it returns. This does not stream per-job progress yet; that would require a separate async job/progress endpoint.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added extraction processing feedback to prevent repeated Process pending clicks. Process buttons now route through a shared app-level handler, are disabled while work is in flight, and open a blocking modal with queued count, animated progress, final processed/succeeded/failed counts, error display, retry, and refresh controls. The extraction API helper now returns the summary instead of immediately reloading so the UI can show completion details first.

Verification: .venv/bin/python -m pytest -> 36 passed; .venv/bin/python -m compileall src/jobhunt -> passed; static search found no stale direct processExtractions alert handlers.
<!-- SECTION:FINAL_SUMMARY:END -->
