---
id: TASK-542
title: 'UI: surface degraded LLM queue errors outside the Queue screen'
status: To Do
assignee: []
created_date: '2026-06-19 07:29'
labels:
  - audit
  - ux
  - llm
  - queue
  - diagnostics
dependencies: []
references:
  - core/LLM/QueueActor.swift
  - app/Platform/PlatformIntegration.swift
  - app/Views/Queue/LLMQueueView.swift
  - app/Shell/AppServices.swift
  - app/Views/Components/ToastView.swift
  - tests/CoreTests/ExtractionEngineTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: `QueueActor` emits `.queueError` when it cannot read queued work or cannot persist failure/cancellation state. `LLMQueueView` shows an in-view error banner and toast if that screen is mounted, but `PlatformIntegration` only logs `.queueError` with `NSLog`. If the user is working in Jobs, Dashboard, or Settings when the queue degrades, the event can be missed unless they later open the Queue screen.

Why this matters: `.queueError` represents a degraded state, not a normal failed request. Work may be stuck or failure state may not be persisted. This is a workflow visibility problem: the app already treats provider-not-configured and auto-pause as user-facing operational states, but store-level queue errors are less visible even though they can block all background AI work.

Suggested implementation: route queue errors through an app-level user-facing channel as well as the queue-local banner. Options: inject/use `ToastStore` in `PlatformIntegration`, add an app-level observable queue health state in `AppServices`, or post a notification that deep-links to the LLM Queue. Keep the existing queue banner, but ensure the same error is visible from any current screen and recorded in recent diagnostics.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A `.queueError` emitted while the user is not on the LLM Queue produces a visible in-app error or notification.
- [ ] #2 The visible error deep-links or points to the LLM Queue for details/retry actions.
- [ ] #3 The existing LLM Queue local banner behavior remains intact when the screen is open.
- [ ] #4 The error is recorded in recent diagnostics without leaking secrets.
- [ ] #5 Provider-not-configured and auto-pause notifications continue to behave as before.
- [ ] #6 Tests or a UI-level seam verify a queue error is surfaced globally, not only to `LLMQueueView`.
<!-- AC:END -->
