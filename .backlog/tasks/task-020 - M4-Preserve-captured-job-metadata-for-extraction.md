---
id: TASK-020
title: 'M4: Preserve captured job metadata for extraction'
status: Done
assignee:
  - Codex
created_date: '2026-05-27 07:45'
updated_date: '2026-05-27 07:53'
labels:
  - m4
  - extraction
  - bug
dependencies: []
modified_files:
  - src/jobhunt/cleaning.py
  - tests/test_db.py
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Fix extraction misses caused by cleaning away visible job metadata such as Workday location and employment blocks. Cleaned descriptions should retain relevant metadata before the job description so the LLM can extract location, remote type, employment type, and requisition fields reliably.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Cached Workday/NVIDIA-style captures preserve visible location metadata in cleaned_description when JSON-LD description omits it.
- [x] #2 Structured JobPosting metadata such as title, employment type, job location, and requisition identifier is included in the text sent to extraction when available.
- [x] #3 Existing cleaning behavior for plain selected text remains unchanged.
- [x] #4 Automated regression tests cover the metadata-preservation behavior.
- [x] #5 The existing NVIDIA cached record is repaired or clearly identified as needing reprocessing after the cleaner fix.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Extend cleaning.py so JSON-LD JobPosting descriptions are prefixed with useful metadata extracted from structured data and visible Workday header blocks.
2. Keep selected_text precedence unchanged so manual selections remain exactly what the user selected.
3. Add regression tests for JSON-LD metadata and Workday visible locations.
4. Repair the existing NVIDIA capture in the local DB by recomputing cleaned_description/cleaned_hash and queueing extraction for that job, then optionally run extraction if LM Studio is reachable.
5. Run the Python test suite and report the cached-row state after the repair.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Confirmed the NVIDIA capture raw visible text contained the location block, but cleaned_description did not because cleaning preferred the JSON-LD description. The JSON-LD JobPosting itself included only Santa Clara in jobLocation, while the visible Workday header included both Santa Clara and Remote. Updated cleaning to prepend structured metadata and visible Workday header metadata when using JSON-LD descriptions. Repaired local capture cap_d7637cdee83b4cedb693d5e0be967626 and re-ran one extraction successfully.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Fixed location extraction misses caused by dropping job metadata during cleaning. JSON-LD JobPosting descriptions now preserve useful metadata before the description, including title, employment type, job ID, structured jobLocation, and Workday-style visible header values such as locations/time type/requisition ID. Selected-text captures remain unchanged. Added a regression test covering the NVIDIA/Workday pattern.

Repaired the existing NVIDIA cached row: cleaned_description now includes `US, CA, Santa Clara` and `US, NC, Remote`, then extraction was rerun successfully. The job now has location `US, CA, Santa Clara; US, NC (Remote options available)` and remote_type `hybrid`.

Verification: .venv/bin/python -m pytest -> 37 passed.
<!-- SECTION:FINAL_SUMMARY:END -->
