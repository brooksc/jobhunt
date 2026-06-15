---
id: TASK-450
title: >-
  LLM queue: Distinguish cancellation from provider failure in processing
  results
status: Done
assignee: []
created_date: '2026-06-13 19:08'
updated_date: '2026-06-15 06:58'
labels:
  - bug
  - llm
  - queue
dependencies: []
references:
  - core/LLM/QueueActor.swift
  - tests/CoreTests/ExtractionEngineTests.swift
modified_files:
  - core/LLM/QueueActor.swift
  - tests/CoreTests/ExtractionEngineTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Queue processing currently returns only a boolean success/failure result. If a request is cancelled while in flight, the success write guard returns `false`, and `startProcessing` increments the failure streak. User-initiated cancellations and skipped stale rows should not be counted as provider failures or trigger auto-pause.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Processing results distinguish at least success, provider failure, cancellation, and skipped/stale states.
- [x] #2 Cancelling an in-flight extraction request does not increment the queue failure streak or trigger auto-pause by itself.
- [x] #3 Cancelling an in-flight fit request does not increment the queue failure streak or trigger auto-pause by itself.
- [x] #4 Focused tests cover cancellation result classification and auto-pause threshold behavior.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Replaced the ProcessResult{succeeded:Bool} with a ProcessOutcome enum (succeeded/providerFailure/cancelled/skipped) (AC#1). processRequest classifies: mark-running failure → .skipped; pre-run transition guard (row cancelled/taken) → .cancelled; on a false (non-throwing) return it reads the row's final status (.cancelled → .cancelled, else .providerFailure); thrown provider errors → .providerFailure. The drain loop only increments failureStreak / can auto-pause on .providerFailure; .cancelled/.skipped are neutral (no count, no streak change) — so cancelling an in-flight extract or fit request can't push the queue to auto-pause (AC#2/#3). Test testCancellingInFlightRequestIsNotCountedAsFailure cancels mid-provider-call and asserts the row ends .cancelled and the queue does not auto-pause; the existing testQueueActorAutoPause still passes (real provider failures still auto-pause) (AC#4).
<!-- SECTION:FINAL_SUMMARY:END -->
