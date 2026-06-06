---
id: TASK-021
title: 'M4: Normalize salary ranges for filtering'
status: Done
assignee:
  - Codex
created_date: '2026-05-27 07:56'
updated_date: '2026-05-27 17:17'
labels:
  - m4
  - extraction
  - salary
dependencies: []
modified_files:
  - src/jobhunt/models.py
  - src/jobhunt/db.py
  - src/jobhunt/api.py
  - src/jobhunt/export.py
  - src/jobhunt/extract.py
  - src/jobhunt/static/main.jsx
  - src/jobhunt/static/screens/detail.jsx
  - src/jobhunt/static/screens/jobs.jsx
  - tests/test_extract.py
  - tests/test_export.py
  - tests/test_db.py
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Ensure extracted salary data stores absolute numeric min/max values for filtering, even when job postings show multiple salary bands by location, seniority, or level. Preserve the original salary context in a separate note for review.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Extraction prompt explicitly instructs the model to use the absolute lowest lower bound and absolute highest upper bound across multiple displayed salary bands.
- [x] #2 Schema and models include a salary_note field that preserves the salary context or original range text when present.
- [x] #3 Database migration handles existing local databases without destructive rebuilds.
- [x] #4 UI displays min/max salary and exposes salary note/context where useful.
- [x] #5 CSV export includes salary_note.
- [x] #6 Existing jobs are queued and reprocessed so salary fields use the updated extraction rules.
- [x] #7 Automated tests cover salary_note persistence/export and prompt parsing expectations.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Add salary_note to ExtractedJob, jobs schema, migration handling, dashboard dataclasses, API UI data, and CSV export.
2. Update mark_extraction_succeeded to persist salary_note and include it in extracted_json.
3. Update the extraction prompt to explicitly require absolute salary_min/salary_max across all bands and preserve original salary context in salary_note.
4. Update UI mapping/detail display to surface salary_note and keep salary filter based on numeric max/min semantics.
5. Add tests for schema migration, extraction parsing, persistence, export, and prompt text.
6. Queue existing jobs for reprocessing by resetting extraction status, run extraction against LM Studio, then verify stored salary fields.
7. Run the full test suite.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Added salary_note as an additive field while retaining salary_min and salary_max as numeric filtering fields. Existing local DB was migrated in place. Reprocessed all five existing jobs through LM Studio with the updated prompt. Four succeeded and now include salary_note where salary text is present; one Microsoft careers capture failed twice because LM Studio returned no JSON, so it remains failed/retryable rather than storing guessed data.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Implemented salary normalization for filtering. The extraction prompt now explicitly requires salary_min to be the absolute lowest lower bound and salary_max to be the absolute highest upper bound across all salary bands, with salary_note preserving original/contextual salary text. Added salary_note to the ExtractedJob model, SQLite jobs schema with in-place migration, extraction persistence, UI data API, web UI mapping/detail display, and CSV export. Updated salary filtering to compare against salaryMax so jobs whose top-end overlaps the threshold are included.

Reprocessed existing data: 5 jobs were queued. 4 succeeded with updated salary values/notes. One Microsoft Careers capture remains failed/retryable after two attempts because the local model response did not contain JSON.

Verification: .venv/bin/python -m pytest -> 40 passed; .venv/bin/python -m compileall src/jobhunt -> passed earlier in this change set.
<!-- SECTION:FINAL_SUMMARY:END -->
