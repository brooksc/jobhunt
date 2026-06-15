---
id: TASK-448
title: 'Manual URL ingest: Avoid duplicate extraction queue requests'
status: Done
assignee: []
created_date: '2026-06-13 19:08'
updated_date: '2026-06-15 05:08'
labels:
  - bug
  - ingestion
  - llm
dependencies: []
references:
  - core/Services/BackgroundStore.swift
  - core/Services/JobService.swift
  - tests/CoreTests/JobServiceTests.swift
modified_files:
  - core/Services/JobService.swift
  - tests/CoreTests/JobServiceTests.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Manual URL ingestion can create two extraction `LLMRequest` rows for one new job. `BackgroundStore.insertCaptureAtomically` already inserts an extraction request with the new capture and job, then `JobService.addJobByURL` calls `queue.enqueue` again when the insert is not a duplicate. Manual URL jobs should produce only one active extraction request by default.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Adding a new job by URL creates exactly one extraction `LLMRequest` for that job.
- [x] #2 Duplicate URL submissions do not create additional extraction requests.
- [x] #3 Browser capture ingestion still creates one extraction request for new non-duplicate jobs.
- [x] #4 Regression tests cover the manual URL ingest path and the normal capture ingest path.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Distinct from TASK-441 (do not auto-queue extraction for semantic *duplicate* jobs). This task is the double-enqueue bug on the manual add-by-URL path (insertCaptureAtomically enqueues, then addJobByURL enqueues again). Same file, different defects — kept separate intentionally.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Investigated and found the reported double-enqueue does NOT occur in current code: insertCaptureAtomically inserts the .queued extraction request, and addJobByURL's queue.enqueue dedups against existing queued/running requests for the same (job, mode) — so it creates no second request and only serves to kick the drain loop (insertCaptureAtomically doesn't start processing). Verified with three new regression tests, all asserting exactly one extraction request: new manual-URL add (AC#1), duplicate URL resubmission (AC#2), and normal browser capture ingest (AC#3); AC#4 satisfied. Added a comment in addJobByURL documenting that the enqueue's purpose is to kick the drain (not redundant) so it isn't removed — which would leave manual-URL jobs unprocessed (the same class of bug as TASK-465).
<!-- SECTION:FINAL_SUMMARY:END -->
