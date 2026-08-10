---
id: TASK-557
title: >-
  Apply minimum window size from a window lifecycle hook instead of
  NSApp.mainWindow at startup
status: Done
assignee: []
created_date: '2026-06-19 23:50'
updated_date: '2026-08-10 00:23'
labels:
  - audit
  - lifecycle
  - ui
dependencies: []
references:
  - 'app/Platform/PlatformIntegration.swift:39'
  - 'app/Platform/PlatformIntegration.swift:73'
  - 'app/JobhuntApp.swift:83'
modified_files:
  - app/Platform/WindowPolicy.swift
  - app/Platform/PlatformIntegration.swift
  - core/Services/WindowSizePolicy.swift
  - tests/CoreTests/WindowSizePolicyTests.swift
priority: low
ordinal: 26000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: `PlatformIntegration.start(queue:)` calls `applyWindowPolicy()` immediately during launch (`app/Platform/PlatformIntegration.swift:39`). `applyWindowPolicy()` reads `NSApp.mainWindow` once and sets `minSize` if a main window already exists (`app/Platform/PlatformIntegration.swift:73`). Startup is launched from a `Task` in `JobhuntApp.init` before the SwiftUI `WindowGroup` is guaranteed to have created or made a main window (`app/JobhuntApp.swift:83`). If `NSApp.mainWindow` is nil at that moment, the minimum size policy is silently skipped and never retried.

Why important: this is a lifecycle timing dependency hidden behind a one-shot side effect. Window sizing is user-visible, and the current implementation can behave differently based on launch timing, OS version, or whether a restored window exists. It also makes the policy hard to test because the dependency is global and moment-sensitive.

Suggested implementation: move minimum-size application to a window lifecycle point where the window is known, such as a SwiftUI/AppKit window accessor, scene/window delegate, or `onAppear`-driven helper that receives the concrete `NSWindow`. Keep `PlatformIntegration` focused on notifications/deep links/queue events, or make window policy a small dedicated adapter. Add a lightweight UI/lifecycle test if feasible; otherwise factor the policy into a helper whose behavior can be verified with an `NSWindow` instance.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The minimum window size is applied when a real `NSWindow` exists, independent of launch timing.
- [x] #2 The window policy is not silently skipped when `NSApp.mainWindow` is nil during startup.
- [x] #3 The implementation keeps notification/queue integration separate from window-specific lifecycle code, or documents the adapter boundary clearly.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
#1/#2 The floor is now applied on `NSWindow.didBecomeKeyNotification` plus a sweep of existing windows at start, instead of once from `NSApp.mainWindow` during `PlatformIntegration.start` — which at launch is frequently nil, so the policy applied or didn't depending on timing and never retried. Observing the notification also covers a window opened later in the session.

#3 The adapter boundary is now a file boundary. `WindowSizePolicy` (Core) holds the numbers and the which-windows rule as plain inputs; `WindowPolicy` (app) is the only AppKit-aware part, reading flags off each window and asking Core. Core rather than app because **the app target has no unit-test target** — only XCUITest, which needs a graphical session — so an `NSWindow`-shaped rule would have had no coverage at all. Panels and the SwiftUI Settings scene are excluded: they size from their content, and forcing 900×600 on Settings would make it enormous.

Worth noting: the compiler-warning ratchet added an hour earlier (TASK-570) caught two new warnings from this change's `deinit` — reaching a non-Sendable observer token from a nonisolated deinit is a Swift 6 error. Removed rather than baselined; the observer block captures no `self`, so an un-removed one holds nothing alive.

5 tests. Gate: fast gate TEST SUCCEEDED, swiftlint 0 violations in 342 files, swiftformat clean, warning ratchet back at 58/58.

not verified: (visual) — that a window can no longer be dragged below 900×600 in a running app. The rule is unit-tested; the AppKit wiring is compile-checked only.
<!-- SECTION:FINAL_SUMMARY:END -->
