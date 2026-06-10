---
id: TASK-092
title: >-
  Fix LLMQueueView + QueueActor: Process/Resume when paused, resume doesn't
  restart, dead code
status: To Do
assignee: []
created_date: '2026-06-10 07:31'
labels:
  - bug
  - ui-audit
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
HIGH: `Process All` and `Process Selected` call `startProcessing()` which immediately exits when `llmQueuePaused == true`. Buttons should be disabled when paused, or automatically unpause first.

HIGH: `resumeQueue()` in QueueActor sets `llmQueuePaused = false` but does NOT call `startProcessing()`. After resuming, queued items sit idle. Fix: call `startProcessing()` after unpausing.

MEDIUM: `processAll()` dead code — computes `pendingJobIDs` but uses it only as a guard, IDs never passed anywhere. Simplify to just call `startProcessing()`.

MEDIUM: `Cancel Selected` always clears selection even on partial failure — user loses selection and can't retry failed cancellations.

LOW: `isPaused` not reset to false on `processingComplete` event.
LOW: Cancel Queued and Process All buttons should be disabled when queue is empty/nothing queued.

Files: `core/LLM/QueueActor.swift`, `app/Views/Queue/LLMQueueView.swift`
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Process All and Process Selected are disabled (or auto-unpause) when queue is paused
- [ ] #2 Resuming the queue immediately starts processing without user clicking Process All
- [ ] #3 processAll() simplified — no dead pendingJobIDs computation
- [ ] #4 Cancel Selected only clears selection for successfully cancelled items
- [ ] #5 isPaused resets on processingComplete
- [ ] #6 Buttons disabled when there's nothing to act on
<!-- AC:END -->
