---
id: TASK-557
title: >-
  Apply minimum window size from a window lifecycle hook instead of
  NSApp.mainWindow at startup
status: To Do
assignee: []
created_date: '2026-06-19 23:50'
updated_date: '2026-07-21 22:59'
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
  - app/Platform/PlatformIntegration.swift
  - app/JobhuntApp.swift
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
- [ ] #1 The minimum window size is applied when a real `NSWindow` exists, independent of launch timing.
- [ ] #2 The window policy is not silently skipped when `NSApp.mainWindow` is nil during startup.
- [ ] #3 The implementation keeps notification/queue integration separate from window-specific lifecycle code, or documents the adapter boundary clearly.
<!-- AC:END -->
