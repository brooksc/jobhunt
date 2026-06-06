---
id: TASK-008
title: Implement CSV export for tracked jobs
status: Done
assignee: []
created_date: '2026-05-27 04:36'
updated_date: '2026-05-27 05:36'
labels:
  - m4-export-workflow
  - export
  - server
dependencies:
  - TASK-007
modified_files:
  - src/jobhunt/cli.py
  - src/jobhunt/db.py
  - src/jobhunt/export.py
  - tests/test_export.py
  - tests/test_dashboard.py
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Add a spreadsheet-friendly export path from SQLite so captured and extracted jobs can be reviewed outside the app. CSV is the first export target; Google Sheets sync remains a future enhancement.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `uv run jobhunt export csv` writes a CSV file containing tracked jobs
- [x] #2 The CSV includes capture ID job ID status company title location remote type salary fields source URL captured_at and extracted_at
- [x] #3 The export omits raw page text by default
- [x] #4 Rows remain traceable back to the source capture through stable IDs
- [x] #5 Focused tests cover CSV output columns and raw text omission
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Implement a small CSV exporter backed by the existing dashboard job query. Expose it as `uv run jobhunt export csv`, default to stdout unless an output path is provided, and cover columns/raw-text omission with tests.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented `jobhunt export csv` with stdout default and optional `--output` path. Export uses the dashboard job read model and omits selected_text visible_text and cleaned_description. Verification used `.venv/bin/jobhunt` because the local uv command is currently shadowed by a broken pmg shim at /Users/brooksc/.pmg/bin/uv.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added CSV export for tracked jobs. The command emits stable traceability columns including capture_id job_id status company title location remote type salary source URL captured_at and extracted_at while omitting raw page text. Tests cover column output and raw text omission.
<!-- SECTION:FINAL_SUMMARY:END -->
