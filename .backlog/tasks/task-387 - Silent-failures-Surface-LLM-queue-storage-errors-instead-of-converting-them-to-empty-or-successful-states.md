---
id: TASK-387
title: >-
  Silent failures: Surface LLM queue storage errors instead of converting them
  to empty or successful states
status: To Do
assignee: []
created_date: '2026-06-12 22:57'
updated_date: '2026-06-14 00:19'
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
- [ ] #5 Genuinely empty queue (no fetch error) still emits the normal empty-completion event; tests cover both the fetch-failure path and the normal empty-queue path (folded in from closed duplicate TASK-451).
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
TASK-451 (2026-06-13) closed as a subset of this task — its scope (surface fetch failures instead of reporting an empty queue) is fully covered by AC#1 here. Its narrower test nuance was folded into the AC list above.
<!-- SECTION:NOTES:END -->
