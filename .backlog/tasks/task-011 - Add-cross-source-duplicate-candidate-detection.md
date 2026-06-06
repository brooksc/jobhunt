---
id: TASK-011
title: Add cross-source duplicate candidate detection
status: Done
assignee: []
created_date: '2026-05-27 04:37'
updated_date: '2026-05-27 05:39'
labels:
  - m4-export-workflow
  - dedup
  - server
dependencies:
  - TASK-007
modified_files:
  - src/jobhunt/cli.py
  - src/jobhunt/db.py
  - tests/test_duplicates.py
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Use stored cleaned job descriptions and extracted job fields to identify likely duplicate postings across different URLs or job boards. The MVP should already store cleaned_description and cleaned_hash; this task adds a dedicated workflow for surfacing likely duplicate jobs without deleting any captures.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A command or helper can find jobs with identical cleaned_hash across different URLs
- [x] #2 Duplicate candidates are recorded without deleting raw captures or job rows
- [x] #3 Candidate output includes enough context to compare source URL company title and cleaned hash
- [x] #4 The workflow leaves room for future fuzzy matching using company title location and similarity scoring
- [x] #5 Focused tests cover identical cleaned description across different URLs
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Add duplicate candidate read helpers that group jobs by identical cleaned_hash across different URLs. Expose a read-only `duplicates list` command that prints enough context for manual comparison and does not modify or delete any rows.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Added read-only duplicate candidate detection grouped by identical cleaned_hash across distinct source URLs. Exposed `jobhunt duplicates list`. It reports cleaned hash plus job ID capture ID company title and source URL and does not merge delete or mutate rows. The user's current DB has no duplicate groups, so the command prints no rows.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added cross-source duplicate candidate reporting. The helper and CLI command find jobs with identical cleaned descriptions across different URLs and print enough context for manual review while preserving all capture and job rows. Tests cover duplicate candidates and same-URL raw duplicate suppression.
<!-- SECTION:FINAL_SUMMARY:END -->
