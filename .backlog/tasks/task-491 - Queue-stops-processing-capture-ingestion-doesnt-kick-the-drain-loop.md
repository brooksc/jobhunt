---
id: TASK-491
title: 'Queue stops processing: capture ingestion doesn''t kick the drain loop'
status: Done
assignee: []
created_date: '2026-06-18 19:16'
labels:
  - bug
  - llm
  - queue
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Recurring bug: the LLM queue stops with requests stuck "Queued" (0 Running) despite not being paused and the provider being available; the user has to hit Resume to continue.

Root cause: `BackgroundStore.insertCaptureAtomically` creates the pending `.extract` LLMRequest directly inside the atomic insert (for transactional integrity), but does NOT kick `QueueActor.startProcessing`. Only `queue.enqueue/enqueueFit/enqueueFitForActiveResumes` (and launch crash-recovery) kick the drain loop. So a capture is only processed if the loop is already running (picked up via per-iteration re-fetch). Once the loop drains and exits (processingComplete), subsequent captures sit Queued with nothing to restart it.

Fix: add `QueueActor.kick()` (fire-and-forget `Task { startProcessing() }`, idempotent, respects pause) and call it from `JobService.ingestCapture` after a non-duplicate atomic insert. Now every capture (new job or re-capture) restarts the drain loop; a deliberately-paused queue is unaffected (startProcessing bails while paused).

Files: core/LLM/QueueActor.swift, core/Services/JobService.swift.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A capture ingested while the drain loop is idle (not paused) is processed automatically, with no manual Resume
- [ ] #2 A re-capture (same URL, changed content) that re-queues extraction is also picked up
- [ ] #3 A deliberately-paused queue is NOT resumed by a capture
- [ ] #4 Exact-duplicate captures (which queue nothing) don't needlessly kick the queue
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Fixed the recurring "queue stops with work Queued" bug. `insertCaptureAtomically` queues the extraction request directly (transactional), bypassing `queue.enqueue`, so nothing kicked `startProcessing` — captures were only processed if the loop happened to be running, and stranded once it drained. Added `QueueActor.kick()` (fire-and-forget `Task { startProcessing() }`; idempotent via the isRunning guard; respects pause) and call it from `JobService.ingestCapture` when the insert wasn't an exact duplicate (new job or re-capture). Regression test `MockLLMInferenceTests.testCapture_kicksQueue_andProcessesWithoutManualResume` ingests a capture (no enqueue/resume) and asserts it processes to `.succeeded` against the mock LLM. Full fast gate green.
<!-- SECTION:FINAL_SUMMARY:END -->
