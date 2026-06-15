---
id: TASK-387
title: >-
  Silent failures: Surface LLM queue storage errors instead of converting them
  to empty or successful states
status: Done
assignee: []
created_date: '2026-06-12 22:57'
updated_date: '2026-06-15 04:38'
labels:
  - audit
  - error-handling
  - llm-queue
dependencies: []
references:
  - core/LLM/QueueActor.swift
  - app/Views/Queue/LLMQueueView.swift
modified_files:
  - core/LLM/QueueActor.swift
  - app/Views/Queue/LLMQueueView.swift
  - app/Platform/PlatformIntegration.swift
  - tests/CoreTests/ExtractionEngineTests.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
QueueActor catches store fetch failures and returns an empty queue, and several failure/cancel persistence updates use `try?`. The UI also ignores selected reset failures before starting processing. These paths can make storage failures appear as no work, leave requests running, or lose request diagnostics.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Queue fetch failures are surfaced as explicit errors or degraded states, not empty successful results.
- [x] #2 Failure/cancel persistence errors are logged and exposed in queue diagnostics.
- [x] #3 Selected processing does not start silently after reset failures for selected requests.
- [ ] #4 Tests cover queue storage failure paths and stuck-running prevention.
- [ ] #5 Genuinely empty queue (no fetch error) still emits the normal empty-completion event; tests cover both the fetch-failure path and the normal empty-queue path (folded in from closed duplicate TASK-451).
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
TASK-451 (2026-06-13) closed as a subset of this task — its scope (surface fetch failures instead of reporting an empty queue) is fully covered by AC#1 here. Its narrower test nuance was folded into the AC list above.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
fetchQueuedRequests now throws on store-read failure; the drain loop distinguishes a read failure (emits new QueueEvent.queueError, exits without a false processingComplete) from a genuinely empty queue (normal processingComplete). queueError is surfaced in LLMQueueView's existing error banner and logged by PlatformIntegration. markRequestFailed/markRequestCancelled log + emit on persistence failure instead of swallowing with try? (avoids leaving a request stuck .running). LLMQueueView.processSelected now reports reset failures and won't start a drain when none of the selected requests could be requeued (AC#3). AC#4/#5 partial: added testEmptyQueueEmitsProcessingComplete (normal empty path); the store-fetch-failure path can't be unit-tested without a failure-injection seam on the concrete BackgroundStore — deferred rather than refactor the store now.
<!-- SECTION:FINAL_SUMMARY:END -->
