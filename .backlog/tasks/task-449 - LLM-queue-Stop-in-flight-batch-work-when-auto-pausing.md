---
id: TASK-449
title: 'LLM queue: Stop in-flight batch work when auto-pausing'
status: Done
assignee: []
created_date: '2026-06-13 19:08'
updated_date: '2026-06-15 18:48'
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
`QueueActor.startProcessing` launches a provider-concurrency batch before observing failures. When the auto-pause threshold is reached, it pauses and breaks from result handling, but already-started sibling tasks can continue provider calls. Auto-pause should prevent additional cloud cost beyond the requests that must finish, or explicitly cancel remaining batch work.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 When auto-pause triggers, no additional queued requests from the same batch begin provider execution after the pause decision.
- [x] #2 Already-started tasks either observe cancellation before calling the provider or are intentionally allowed to finish with documented behavior.
- [x] #3 Queue completion accounting remains accurate after auto-pause cancellation or early stop.
- [x] #4 Focused tests cover auto-pause behavior with a provider concurrency limit greater than one.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Merged near-duplicate TASK-380 (audit batch, 2026-06-12) into this task — same root issue: startProcessing launches the whole provider-concurrency batch, and auto-pause does not cancel already-started sibling tasks. This task supersedes 380. Note: TASK-450 (classify cancellation vs provider failure in results) is a distinct follow-on and is intentionally kept separate.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
On hitting the auto-pause threshold, startProcessing now calls group.cancelAll() alongside pausing + emitting .autoPaused. processRequest checks Task.isCancelled after claiming the row and, if cancelled, re-queues it (.running→.queued) and returns .cancelled WITHOUT calling the provider — so a sibling task that hasn't reached its provider call doesn't begin one (AC#1). Already-running provider calls observe cancellation through URLSession; the documented behavior is that the row is returned to .queued for the next resume (AC#2). Completion accounting stays correct: cancelled outcomes are discarded (the result loop already broke) and unfetched batch members remain queued (AC#3). Test testAutoPause_withConcurrencyGreaterThanOne (concurrencyLimit 3, 5 failing jobs) asserts the queue auto-pauses and leaves remaining work queued rather than draining all five; existing single-width auto-pause + cancellation tests still pass (AC#4).
<!-- SECTION:FINAL_SUMMARY:END -->
