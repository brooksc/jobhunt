---
id: TASK-447
title: 'LLM queue: Preserve cancellation during retry backoff'
status: To Do
assignee: []
created_date: '2026-06-13 19:07'
labels:
  - bug
  - llm
  - queue
dependencies: []
references:
  - core/LLM/QueueActor.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Cancelling an LLM request while it is sleeping between retry attempts can be overwritten by the retry handler. `QueueActor.cancelRequest` marks the row `.cancelled`, but extraction and fit failure paths sleep and then unconditionally set the same request back to `.queued`. A user cancellation must remain authoritative so a cancelled cloud request is not retried and billed later.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Cancelling an extraction request during retry backoff leaves the final request status `.cancelled` and does not requeue it.
- [ ] #2 Cancelling a fit-scoring request during retry backoff leaves the final request status `.cancelled` and does not requeue it.
- [ ] #3 Retry requeue logic only updates requests that are still eligible for the same retry attempt and have not been cancelled or otherwise terminalized.
- [ ] #4 Focused tests cover cancellation during retry backoff for both extraction and fit requests.
<!-- AC:END -->
