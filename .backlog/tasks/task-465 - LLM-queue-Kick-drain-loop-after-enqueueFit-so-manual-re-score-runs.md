---
id: TASK-465
title: 'LLM queue: Kick drain loop after enqueueFit so manual re-score runs'
status: To Do
assignee: []
created_date: '2026-06-15 03:38'
labels:
  - bug
  - llm
  - queue
dependencies: []
references:
  - core/LLM/QueueActor.swift
  - app/Views/Detail/JobDetailView.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`QueueActor.enqueueFit(jobIDs:resumeID:)` inserts `.queued` fit requests via `store.insertFitBatch` but, unlike its siblings `enqueue` (line 119) and `enqueueFitForActiveResumes` (line 146), never calls `Task { await startProcessing() }`. The only production caller is the "Score against resume" / re-score button in `JobDetailView.swift:872`, which also does not kick the queue. Result: clicking re-score creates a request that sits `.queued` indefinitely until some unrelated event (a new capture, app relaunch via requeueRunningOnLaunch) starts the loop. Unit tests mask this because they call `startProcessing()` explicitly right after `enqueueFit`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 enqueueFit starts the drain loop (Task { await startProcessing() }) after a successful batch insert, mirroring enqueue
- [ ] #2 A manual re-score from JobDetailView produces a fit score without any other queue-triggering event
- [ ] #3 A focused test verifies enqueueFit alone (without an explicit startProcessing call) drains the queued fit request
<!-- AC:END -->
