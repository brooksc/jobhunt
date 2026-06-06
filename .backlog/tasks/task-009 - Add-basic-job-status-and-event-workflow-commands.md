---
id: TASK-009
title: Add basic job status and event workflow commands
status: Done
assignee: []
created_date: '2026-05-27 04:36'
updated_date: '2026-05-27 05:38'
labels:
  - m4-export-workflow
  - workflow
  - server
dependencies:
  - TASK-002
modified_files:
  - src/jobhunt/cli.py
  - src/jobhunt/db.py
  - tests/test_workflow.py
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Add minimal local workflow commands for changing job status and recording timeline events after jobs have been captured and extracted. This keeps the job search tracker useful before a dedicated UI exists.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A CLI command can list tracked jobs with IDs status company title and source URL
- [x] #2 A CLI command can update a job status to one of the MVP statuses in spec.md
- [x] #3 Changing status records a status_changed event with timestamp
- [x] #4 A CLI command can add a note event to a job
- [x] #5 Focused tests cover status validation status updates and event creation
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Add workflow helpers in db.py for listing jobs, validating/updating status, and appending note events. Expose them through Typer commands `jobs list`, `jobs status`, and `jobs note`, then test status validation and event creation.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Added `jobhunt jobs list`, `jobhunt jobs status`, and `jobhunt jobs note`. Status changes validate against MVP statuses and append status_changed events. Notes append note_added events. Verified against the real DB with `.venv/bin/jobhunt jobs list` due the local uv/pmg shim issue.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added basic workflow commands for local job management. Users can list tracked jobs, update a job status with validation, and add note events from the CLI. Tests cover job listing, status updates, invalid status rejection, and note event creation.
<!-- SECTION:FINAL_SUMMARY:END -->
