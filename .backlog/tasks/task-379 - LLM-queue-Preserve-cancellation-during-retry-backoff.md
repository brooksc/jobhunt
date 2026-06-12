---
id: TASK-379
title: 'LLM queue: Preserve cancellation during retry backoff'
status: To Do
assignee: []
created_date: '2026-06-12 22:55'
labels:
  - audit
  - concurrency
  - llm-queue
  - cancellation
dependencies: []
references:
  - core/LLM/QueueActor.swift
  - tests/CoreTests/ExtractionEngineTests.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
When extract or fit processing fails below max retries, QueueActor sleeps for backoff and then unconditionally requeues the request. A user cancellation during the sleep can be overwritten back to queued.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 After retry backoff, QueueActor only requeues a request if it is still in the expected running/retryable state.
- [ ] #2 Cancellation during extract and fit backoff remains cancelled and does not restart processing.
- [ ] #3 Regression tests cover cancellation during retry backoff for extract and fit requests.
<!-- AC:END -->
