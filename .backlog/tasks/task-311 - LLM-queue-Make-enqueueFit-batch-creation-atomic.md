---
id: TASK-311
title: 'LLM queue: Make enqueueFit batch creation atomic'
status: To Do
assignee: []
created_date: '2026-06-12 19:35'
labels:
  - audit
  - llm-queue
  - persistence
dependencies: []
references:
  - core/LLM/QueueActor.swift
  - core/Services/BackgroundStore.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
QueueActor.enqueueFit inserts each LLMRequest and pending JobFitScore separately inside a loop. If one insert or pending-state update fails midway, the batch can partially enqueue, unlike extraction enqueue which builds requests and saves as a batch.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 enqueueFit creates the intended request and pending-score records atomically for the requested job set, or reports partial failures explicitly.
- [ ] #2 Duplicate or missing jobs/resumes have documented behavior consistent with extraction enqueue.
- [ ] #3 Tests cover multi-job enqueueFit success and failure/partial-input behavior.
<!-- AC:END -->
