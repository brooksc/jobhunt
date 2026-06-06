---
id: TASK-022
title: 'M4: Add short job numbers and improve failed Microsoft extraction'
status: Done
assignee:
  - Codex
created_date: '2026-05-27 17:33'
updated_date: '2026-05-27 17:41'
labels:
  - m4
  - web
  - extraction
  - ux
dependencies: []
modified_files:
  - src/jobhunt/db.py
  - src/jobhunt/cleaning.py
  - src/jobhunt/api.py
  - src/jobhunt/export.py
  - src/jobhunt/dashboard.py
  - src/jobhunt/cli.py
  - src/jobhunt/static/main.jsx
  - src/jobhunt/static/screens/jobs.jsx
  - src/jobhunt/static/screens/detail.jsx
  - tests/test_db.py
  - tests/test_dashboard.py
  - tests/test_export.py
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Add stable numeric job numbers that users can reference in conversation and the UI, and investigate/fix the failed Microsoft Careers extraction where the LLM returned no JSON despite a captured job detail page.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Each job has a stable numeric job number assigned in the database and preserved across reloads.
- [x] #2 Existing jobs are backfilled with job numbers without changing UUID job IDs or relationships.
- [x] #3 The jobs table and job detail panel display the short job number clearly.
- [x] #4 API and CSV export include the short job number.
- [x] #5 Failed Microsoft Careers capture is diagnosed and either successfully reprocessed or left with a clearer actionable failure state.
- [x] #6 Automated tests cover job number assignment migration API data and export behavior.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Add stable numeric job_number to jobs schema, migration, API responses, export, and UI surfaces. Verify with DB/API/export tests.
2. Improve Microsoft Careers fallback cleaning so extraction receives the actual job detail instead of the whole search/page shell. Verify with a focused cleaning regression test.
3. Repair and reprocess the failed Microsoft capture, then run the relevant test suite.
<!-- SECTION:PLAN:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added stable numeric job numbers with migration/backfill, API and CSV export support, and visible UI labels in the jobs table and detail panel. Improved Microsoft Careers fallback cleaning to extract the detail section and metadata instead of search/page shell text. Repaired and reprocessed the failed Microsoft capture; job #4 now extracts successfully as Microsoft Senior Product Manager with location, remote type, salary range, and skills. Verified with full pytest suite.
<!-- SECTION:FINAL_SUMMARY:END -->
