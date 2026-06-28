---
id: TASK-528
title: >-
  Queue lifecycle: replace fire-and-forget drain kicks with tracked processing
  tasks
status: Done
assignee: []
created_date: '2026-06-19 04:45'
updated_date: '2026-06-28 00:51'
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
modified_files:
  - core/LLM/QueueActor.swift
  - app/Shell/AppServices.swift
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
- [x] #1 Queue-triggered drain work has an explicit owner or stored task handle instead of anonymous fire-and-forget tasks.
- [x] #2 App shutdown or queue teardown can cancel any active drain task intentionally.
- [x] #3 Enqueue, kick, resume, and manual process-all still avoid duplicate concurrent drain loops.
- [x] #4 Errors that currently surface via queue events continue to surface after the task-ownership change.
- [x] #5 Focused tests cover multiple rapid enqueue/kick calls, paused queue behavior, and shutdown/cancellation semantics.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Gave the queue's kick-initiated drains an explicit owner.

- Added `drainTask: Task<Void, Never>?` to QueueActor and a guarded `startProcessingIfNeeded()` that spawns the drain only when no tracked drain is outstanding (`drainTask == nil`), storing the handle and clearing it via `finishDrain()` when the loop ends (so a later kick starts a fresh drain). Replaced the four anonymous `Task { await startProcessing() }` kicks (enqueue, enqueueFit, enqueueFitForActiveResumes, kick) with it; resumeQueue now uses the same tracked path and returns promptly instead of awaiting a full drain. (AC#1)
- Added `cancelProcessing()` — cancels the tracked drain and awaits its exit — and called it inside `AppServices.shutdown()`'s finalize so a UI-initiated drain is cancelled+awaited before shutdown returns (the runtime only owns the launch crash-recovery drain). Upholds the TASK-555 quiescing contract. (AC#2)
- The internal `isRunning` guard still prevents duplicate concurrent loops across both the tracked path and direct `startProcessing()` callers (launch task + tests). (AC#3)
- `startProcessing()` stays public/awaitable, so queue events (.autoPaused, .processingComplete, etc.) surface exactly as before. (AC#4)

Tests (AC#5): `testRapidKicks_drainOnceThenRestartAfterCompletion` (rapid enqueue+kick → single drain to success, then a later enqueue restarts the drain — proves handle cleared); `testPausedQueue_kickLeavesWorkQueued` (paused → kicked work stays queued, provider never called); `testCancelProcessing_stopsActiveDrain` (cancels an in-flight 10s drain and returns promptly, request not succeeded). The existing `testEnqueueFit_drainsWithoutExplicitStartProcessing` still passes (kick path). Full fast gate (CoreTests/ServerTests/MCPTests) green; app target builds with the shutdown change.
<!-- SECTION:FINAL_SUMMARY:END -->
