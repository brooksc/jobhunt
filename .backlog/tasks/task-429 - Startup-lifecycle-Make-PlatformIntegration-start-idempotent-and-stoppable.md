---
id: TASK-429
title: 'Startup lifecycle: Make PlatformIntegration start idempotent and stoppable'
status: To Do
assignee: []
created_date: '2026-06-13 04:34'
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
- [ ] #1 Calling `PlatformIntegration.start(queue:)` more than once does not duplicate queue subscriptions, notification observers, delegates, or OS permission prompts.
- [ ] #2 `PlatformIntegration` exposes or owns a cleanup path that cancels its queue subscription and unregisters observers when appropriate.
- [ ] #3 Production launch still starts platform integration once and preserves current notification/deep-link behavior.
- [ ] #4 Add focused lifecycle coverage or unit-testable seams for repeated start/stop behavior.
<!-- AC:END -->
