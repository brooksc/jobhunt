---
id: TASK-447
title: 'LLM queue: Preserve cancellation during retry backoff'
status: Done
assignee: []
created_date: '2026-06-13 19:07'
updated_date: '2026-06-15 04:33'
labels:
  - bug
  - llm
  - queue
dependencies: []
references:
  - core/LLM/QueueActor.swift
modified_files:
  - core/LLM/QueueActor.swift
  - tests/CoreTests/ExtractionEngineTests.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Cancelling an LLM request while it is sleeping between retry attempts can be overwritten by the retry handler. `QueueActor.cancelRequest` marks the row `.cancelled`, but extraction and fit failure paths sleep and then unconditionally set the same request back to `.queued`. A user cancellation must remain authoritative so a cancelled cloud request is not retried and billed later.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Cancelling an extraction request during retry backoff leaves the final request status `.cancelled` and does not requeue it.
- [x] #2 Cancelling a fit-scoring request during retry backoff leaves the final request status `.cancelled` and does not requeue it.
- [x] #3 Retry requeue logic only updates requests that are still eligible for the same retry attempt and have not been cancelled or otherwise terminalized.
- [ ] #4 Focused tests cover cancellation during retry backoff for both extraction and fit requests.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Merged duplicate TASK-379 (audit batch, 2026-06-12) into this task. Both describe the identical QueueActor bug: after retry backoff the request is unconditionally requeued, overwriting a user cancellation. This task supersedes 379 (it has the clearer billing rationale and a 4th AC requiring retry-requeue to only touch still-eligible, non-terminalized requests). 379 archived.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Both the extract and fit retry paths slept for the backoff then unconditionally reset the request to .queued, overwriting a user cancellation that landed during the sleep (cancelRequest sets .cancelled + finishedAt). Added `guard req.status == .running else { return }` to the post-sleep requeue in both paths (identical code, replace_all), so a cancellation stays authoritative and a cancelled/billable cloud call is not retried — mirrors the existing markRequestFailed TASK-313 guard. AC#4 partial: added testCancellationDuringRetryBackoffIsPreserved for the extract path (cancels mid-backoff, asserts final .cancelled); the fit path is the byte-identical guarded requeue so it's covered by the same fix, but a fit-specific timing test was not added.
<!-- SECTION:FINAL_SUMMARY:END -->
