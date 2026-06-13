---
id: TASK-450
title: >-
  LLM queue: Distinguish cancellation from provider failure in processing
  results
status: To Do
assignee: []
created_date: '2026-06-13 19:08'
labels:
  - bug
  - llm
  - queue
dependencies: []
references:
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
- [ ] #1 Processing results distinguish at least success, provider failure, cancellation, and skipped/stale states.
- [ ] #2 Cancelling an in-flight extraction request does not increment the queue failure streak or trigger auto-pause by itself.
- [ ] #3 Cancelling an in-flight fit request does not increment the queue failure streak or trigger auto-pause by itself.
- [ ] #4 Focused tests cover cancellation result classification and auto-pause threshold behavior.
<!-- AC:END -->
