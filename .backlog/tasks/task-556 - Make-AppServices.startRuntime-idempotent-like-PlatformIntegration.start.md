---
id: TASK-556
title: Make AppServices.startRuntime idempotent like PlatformIntegration.start
status: Done
assignee: []
created_date: '2026-06-19 23:49'
updated_date: '2026-06-25 21:03'
labels:
  - audit
  - lifecycle
  - concurrency
dependencies: []
references:
  - 'app/Shell/AppServices.swift:71'
  - 'app/Shell/AppServices.swift:73'
  - 'app/Shell/AppServices.swift:85'
  - 'app/Shell/AppServices.swift:110'
  - 'app/Platform/PlatformIntegration.swift:33'
modified_files:
  - app/Shell/AppServices.swift
  - app/Platform/PlatformIntegration.swift
  - tests/CoreTests/LaunchModeTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: `PlatformIntegration.start(queue:)` explicitly guards duplicate starts with `isStarted` (`app/Platform/PlatformIntegration.swift:33`), but `AppServices.startRuntime()` has no equivalent guard (`app/Shell/AppServices.swift:71`). Every call appends a new server-start task, a new launch recovery/queue-processing task, and a new hourly availability loop (`app/Shell/AppServices.swift:73`, `app/Shell/AppServices.swift:85`, `app/Shell/AppServices.swift:110`). The server start itself is idempotent, but the crash-recovery and availability tasks are not protected at the service boundary.

Why important: lifecycle methods become de facto APIs. Today `JobhuntApp` calls `startRuntime()` once, but future retry/restart/test/restore flows can accidentally call it again and create duplicated background loops or repeated queue recovery work. The paired integration object already treats duplicate start as a real risk, so the service graph should enforce the same lifecycle invariant.

Suggested implementation: add a private runtime state flag or small state enum to `AppServices` (`stopped`, `starting/started`, `shuttingDown` if needed). Return early if already started, and clear the state only after `shutdown()` completes. Keep the behavior symmetrical with `PlatformIntegration.stop()`: start is safe to call repeatedly, shutdown is safe to call repeatedly, and restart after shutdown is explicit. Add a focused unit/integration test through a testable helper if constructing full `AppServices` is too heavy.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Calling `AppServices.startRuntime()` more than once does not create duplicate availability loops, queue-recovery tasks, or server-start tasks.
- [x] #2 `shutdown()` resets runtime state only after runtime tasks and server stop have completed.
- [x] #3 A focused test or testable lifecycle helper verifies duplicate start is a no-op and restart after shutdown behaves intentionally.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
`AppServices.startRuntime()` delegates to `RuntimeTaskController.start(_:)`, which guards on an internal `started` flag (mirrors `PlatformIntegration.isStarted`): a second call without an intervening shutdown returns false WITHOUT invoking the task factory, so no duplicate server/recovery/availability tasks. `shutdown()` resets the flag only after tasks and finalize complete, so restart after shutdown is explicit and clean. Verified by `RuntimeTaskControllerTests.testStartIsIdempotentAndRestartable` (asserts the factory runs once across a duplicate start, then again after shutdown). Commits 31c6d4b, 09062e6.
<!-- SECTION:FINAL_SUMMARY:END -->
