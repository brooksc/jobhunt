---
id: TASK-452
title: 'Fit scoring: Report invalid resume IDs instead of silently no-oping'
status: Done
assignee: []
created_date: '2026-06-13 19:12'
updated_date: '2026-06-15 19:58'
labels:
  - llm
  - fit-scoring
  - ux
dependencies: []
references:
  - core/LLM/QueueActor.swift
  - tests/CoreTests/JobServiceTests.swift
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`QueueActor.enqueueFit` returns without creating requests when the requested resume ID does not exist. That behavior is currently covered by tests, but it gives callers and users no explanation when fit scoring does nothing. Invalid resume IDs should produce a typed, user-visible failure at the service/UI boundary.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Calling fit enqueue with a missing resume ID produces an explicit typed error or observable user-facing failure state.
- [x] #2 No fit `LLMRequest` rows are created for an invalid resume ID.
- [x] #3 Valid fit enqueue behavior is unchanged for existing resumes.
- [x] #4 Tests cover both invalid-resume and valid-resume enqueue behavior with the new error contract.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
`QueueActor.enqueueFit` now throws a typed `FitEnqueueError.resumeNotFound(resumeID)` (LocalizedError) when the resume ID doesn't exist, instead of silently returning. The throw happens before `insertFitBatch`, so no fit `LLMRequest` rows are created (AC#2), and valid enqueue is unchanged (AC#3). The existing JobDetailView "Score against resume"/rescore caller already wraps the call in try/catch and toasts `error.localizedDescription`, so the failure is now user-visible (AC#1). AC#4: updated the prior no-op test to assert both the typed throw and zero rows; valid-resume enqueue covered by existing tests. CoreTests green; app builds.
<!-- SECTION:FINAL_SUMMARY:END -->
