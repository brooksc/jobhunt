---
id: TASK-448
title: 'Manual URL ingest: Avoid duplicate extraction queue requests'
status: To Do
assignee: []
created_date: '2026-06-13 19:08'
updated_date: '2026-06-14 00:19'
labels:
  - bug
  - ingestion
  - llm
dependencies: []
references:
  - core/Services/BackgroundStore.swift
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
- [ ] #1 Adding a new job by URL creates exactly one extraction `LLMRequest` for that job.
- [ ] #2 Duplicate URL submissions do not create additional extraction requests.
- [ ] #3 Browser capture ingestion still creates one extraction request for new non-duplicate jobs.
- [ ] #4 Regression tests cover the manual URL ingest path and the normal capture ingest path.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Distinct from TASK-441 (do not auto-queue extraction for semantic *duplicate* jobs). This task is the double-enqueue bug on the manual add-by-URL path (insertCaptureAtomically enqueues, then addJobByURL enqueues again). Same file, different defects — kept separate intentionally.
<!-- SECTION:NOTES:END -->
