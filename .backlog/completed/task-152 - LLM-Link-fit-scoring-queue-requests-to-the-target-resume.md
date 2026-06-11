---
id: TASK-152
title: 'LLM: Link fit-scoring queue requests to the target resume'
status: Done
assignee: []
created_date: '2026-06-11 19:31'
updated_date: '2026-06-11 21:11'
labels:
  - llm
  - fit-scoring
  - queue
  - bug
dependencies: []
references:
  - app/Views/Detail/JobDetailView.swift
  - core/LLM/QueueActor.swift
  - core/Models/LLMRequest.swift
modified_files:
  - core/LLM/QueueActor.swift
  - app/Views/Detail/JobDetailView.swift
  - tests/CoreTests/JobServiceTests.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
LLM/extraction audit finding: Job detail enqueues `.fit` requests by job ID only, while `QueueActor.processFitRequest` requires both `jobID` and `resumeID`. Fit requests created through the current generic enqueue path can cancel before calling the provider.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A fit-specific enqueue API creates `LLMRequest(requestType: .fit)` rows linked to both the job and the intended resume.
- [ ] #2 The Score against resume action queues scoring for the active resume when no score exists.
- [ ] #3 The Re-score action queues scoring for the specific resume represented by the selected `JobFitScore`.
- [ ] #4 Tests cover a fit request reaching the provider with a linked resume and no cancellation due to missing `resumeID`.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added `QueueActor.enqueueFit(jobIDs:resumeID:)` that links each LLMRequest to the target resume. Updated FitTabView: "Score against resume" uses `activeResumes.first?.id`; "Re-score" uses `fs.resume?.id`. Two new tests verify resume linkage and graceful handling of unknown resume IDs.
<!-- SECTION:FINAL_SUMMARY:END -->
