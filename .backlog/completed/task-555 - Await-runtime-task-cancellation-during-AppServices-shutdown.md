---
id: TASK-555
title: Await runtime task cancellation during AppServices shutdown
status: Done
assignee: []
created_date: '2026-06-19 23:49'
updated_date: '2026-06-25 21:03'
labels:
  - audit
  - lifecycle
  - concurrency
  - shutdown
dependencies: []
references:
  - 'app/Shell/AppServices.swift:85'
  - 'app/Shell/AppServices.swift:110'
  - 'app/Shell/AppServices.swift:133'
  - TASK-546
modified_files:
  - app/Shell/AppServices.swift
  - tests/CoreTests/LaunchModeTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: `AppServices.shutdown()` cancels every stored runtime task and immediately clears the array before awaiting only `server.stop()` (`app/Shell/AppServices.swift:133`). The runtime tasks include crash-recovery/queue processing and the hourly availability loop (`app/Shell/AppServices.swift:85`, `app/Shell/AppServices.swift:110`). Cancellation is cooperative: a task that is currently inside queue processing or availability checking can continue until its next cancellation check, while `shutdown()` has already returned and discarded the handles.

Why important: `AppServices.shutdown()` is the natural quiescing boundary for termination and for workflows that replace or recover the store. Returning before background tasks finish leaves a window where old runtime work can still read or write through `BackgroundStore`/`SettingsStore` after the app believes services are stopped. This is especially risky near restore/store replacement work (`TASK-546`) and makes lifecycle tests less deterministic.

Suggested implementation: after cancelling runtime tasks, await their completion before clearing the handles. Because the tasks are `Task<Void, Never>`, this can be done by capturing the array, cancelling each task, then `await task.value` for each. Ensure the availability loop exits promptly on sleep cancellation and that queue processing checks cancellation at its existing boundaries. Consider making `shutdown()` idempotent under concurrent calls by taking and clearing the task array before awaiting, then stopping the server.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `AppServices.shutdown()` waits for all previously started runtime tasks to complete after cancellation.
- [x] #2 Concurrent or repeated `shutdown()` calls remain idempotent and do not await the same task set twice unsafely.
- [x] #3 A focused test or testable helper verifies that shutdown does not return before a cancellable runtime task has observed cancellation and exited.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
`AppServices.shutdown()` now delegates to `RuntimeTaskController.shutdown(finalize:)`, which takes the task handles synchronously (before any await), cancels each, then `await task.value` on each before running finalize (server stop) — so crash recovery and the availability loop have provably exited before shutdown returns. Handles are cleared synchronously, so repeated/concurrent calls don't await the same set twice. Verified by `RuntimeTaskControllerTests.testShutdownAwaitsTaskExit` (task sets a flag only after observing cancellation) and `testRepeatedShutdownIsSafe`. Commits 31c6d4b, 09062e6.
<!-- SECTION:FINAL_SUMMARY:END -->
