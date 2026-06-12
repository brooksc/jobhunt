---
id: TASK-387
title: >-
  Silent failures: Surface LLM queue storage errors instead of converting them
  to empty or successful states
status: To Do
assignee: []
created_date: '2026-06-12 22:57'
labels:
  - audit
  - error-handling
  - llm-queue
dependencies: []
references:
  - core/LLM/QueueActor.swift
  - app/Views/Queue/LLMQueueView.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
QueueActor catches store fetch failures and returns an empty queue, and several failure/cancel persistence updates use `try?`. The UI also ignores selected reset failures before starting processing. These paths can make storage failures appear as no work, leave requests running, or lose request diagnostics.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Queue fetch failures are surfaced as explicit errors or degraded states, not empty successful results.
- [ ] #2 Failure/cancel persistence errors are logged and exposed in queue diagnostics.
- [ ] #3 Selected processing does not start silently after reset failures for selected requests.
- [ ] #4 Tests cover queue storage failure paths and stuck-running prevention.
<!-- AC:END -->
