---
id: TASK-542
title: 'UI: surface degraded LLM queue errors outside the Queue screen'
status: Done
assignee: []
created_date: '2026-06-19 07:29'
updated_date: '2026-06-19 23:32'
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

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Auth (401/403) queue failures are now surfaced and actionable instead of a silent "LLM HTTP 401" in the Queue column.

1. **Actionable error text** — LLMProviderError.httpError(401/403).errorDescription → "API key rejected (HTTP 401) — check your AI provider key in Settings"; other codes keep "LLM HTTP <n>". Propagates to the stored req.error via localizedDescription.
2. **Distinct event + notification** — QueueActor classifies 401/403 as ProcessOutcome.authFailure and emits the new QueueEvent.authenticationFailed(statusCode:). PlatformIntegration posts a critical "AI key rejected — check Settings → AI Provider" notification with a fixed id (one alert, not one per job) deep-linking to the AI Provider tab.
3. **Immediate pause** — the drain pauses on the first auth failure and cancels the rest of the batch (a bad key fails every request), rather than exhausting the whole queue.
4. **In-Queue banner** — LLMQueueView shows the same actionable message + toast and reflects the paused state.

Also upgraded the notification settings deep-link to select the AI (.llm) tab (navigate "settings-ai"), which closes TASK-543 for the provider-not-configured nudge too.

Tests: testAuthFailure_pausesQueueAndEmitsAuthenticationFailed (401 → pause + event, integration) and testAuthErrorDescriptionsAreActionable (401/403 actionable, 500 terse, body never leaks). Build + fast gate green. Commit 7434166.

Note on the user's "no notification" report: the app already posts a generic "N jobs failed" notification on processingComplete, but it's easy to miss and says nothing about the key; the unified log showed nothing in the prior 6h. This dedicated auth path doesn't depend on that fragile generic-failure counting.
<!-- SECTION:FINAL_SUMMARY:END -->
