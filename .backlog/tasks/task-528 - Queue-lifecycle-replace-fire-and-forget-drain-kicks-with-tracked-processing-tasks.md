---
id: TASK-528
title: >-
  Queue lifecycle: replace fire-and-forget drain kicks with tracked processing
  tasks
status: To Do
assignee: []
created_date: '2026-06-19 04:45'
labels:
  - audit
  - concurrency
  - queue
  - lifecycle
dependencies: []
references:
  - core/LLM/QueueActor.swift
  - app/Shell/AppServices.swift
  - core/Services/JobService.swift
  - tests/CoreTests/ExtractionEngineTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: several queue entry points call `Task { await startProcessing() }` from inside `QueueActor` methods such as enqueue and kick. These unstructured tasks are not returned to the caller and are not tracked by `AppServices.shutdown()`. The actor-level `isRunning` flag prevents duplicate drain loops, but ownership and cancellation of the spawned task are implicit.

Why this matters: queue processing performs provider calls and store mutations. If processing is started by an untracked task, callers cannot await startup/failure, app shutdown cannot intentionally cancel that specific drain task, and future changes can accidentally create work that outlives the UI or launch mode that requested it.

Suggested implementation: make drain-loop ownership explicit. Options include storing a `Task<Void, Never>?` inside `QueueActor`, exposing a `startProcessingIfNeeded()` that records/cancels the task, or making enqueue/kick return enough information for the app-owned runtime task manager to own the drain. Preserve idempotent behavior and paused-queue semantics.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Queue-triggered drain work has an explicit owner or stored task handle instead of anonymous fire-and-forget tasks.
- [ ] #2 App shutdown or queue teardown can cancel any active drain task intentionally.
- [ ] #3 Enqueue, kick, resume, and manual process-all still avoid duplicate concurrent drain loops.
- [ ] #4 Errors that currently surface via queue events continue to surface after the task-ownership change.
- [ ] #5 Focused tests cover multiple rapid enqueue/kick calls, paused queue behavior, and shutdown/cancellation semantics.
<!-- AC:END -->
