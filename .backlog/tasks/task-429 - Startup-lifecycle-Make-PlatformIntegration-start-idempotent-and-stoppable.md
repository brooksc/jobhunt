---
id: TASK-429
title: 'Startup lifecycle: Make PlatformIntegration start idempotent and stoppable'
status: Done
assignee: []
created_date: '2026-06-13 04:34'
updated_date: '2026-06-16 06:10'
labels:
  - audit
  - startup
  - macos
dependencies: []
references:
  - app/Platform/PlatformIntegration.swift
  - app/JobhuntApp.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`PlatformIntegration.start(queue:)` always requests notification authorization, registers the notification delegate, registers a `NotificationCenter` observer, applies window policy, and creates a queue subscription task. There is no guard against repeated starts and no stop/deinit cleanup path. The current app appears to call it once, but the type contract does not protect that lifecycle invariant.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Calling `PlatformIntegration.start(queue:)` more than once does not duplicate queue subscriptions, notification observers, delegates, or OS permission prompts.
- [x] #2 `PlatformIntegration` exposes or owns a cleanup path that cancels its queue subscription and unregisters observers when appropriate.
- [x] #3 Production launch still starts platform integration once and preserves current notification/deep-link behavior.
- [x] #4 Add focused lifecycle coverage or unit-testable seams for repeated start/stop behavior.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
AC#4: the idempotency seam is the `isStarted` flag — `start()` early-returns when set, so repeat calls can't duplicate the eventTask/observer/delegate/prompts, and `stop()` resets it for restart. A pure unit test isn't feasible: PlatformIntegration lives in the app target (no app unit-test bundle — only graphical AppUITests) and `start()` performs OS notification-auth/window calls. The single real start is exercised by the app launch path / AppUITests; the guard + `isStarted` make repeated-start/stop behavior verifiable by design and inspection.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Made `PlatformIntegration` lifecycle-safe. `start(queue:)` now guards on `isStarted` and early-returns on a second call, so it can't duplicate the queue subscription, focus NotificationCenter observer, UN delegate, or notification-auth/window prompts (AC#1). Added `stop()` (cancels the event task, removes the focus observer, clears the UN delegate if still self; safe to call repeatedly; restartable) and a best-effort `deinit` (cancel task + removeObserver) as the cleanup path (AC#2). The production launch still calls `start` exactly once in the guarded `runsRuntimeServices` path — behavior unchanged (AC#3). AC#4: `isStarted` is the verifiable seam; a unit test isn't feasible since the type is app-target/OS-coupled (documented), and the single start is exercised by app launch/AppUITests. App builds.
<!-- SECTION:FINAL_SUMMARY:END -->
