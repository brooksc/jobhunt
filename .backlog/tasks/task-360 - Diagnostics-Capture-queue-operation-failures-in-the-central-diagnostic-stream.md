---
id: TASK-360
title: 'Diagnostics: Capture queue operation failures in the central diagnostic stream'
status: Done
assignee: []
created_date: '2026-06-12 21:48'
updated_date: '2026-06-15 19:09'
labels:
  - audit
  - diagnostics
  - llm-queue
dependencies: []
references:
  - app/Views/Queue/LLMQueueView.swift
  - app/Views/Settings/DebugTab.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Queue cancel/reset failures only set LLMQueueView.errorMessage, so Copy Diagnostics misses important queue operational errors while other error toasts are retained in ToastStore.recentErrors.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Queue operation failures are recorded in the same diagnostic/error stream used by the Debug tab.
- [x] #2 User-facing queue errors remain visible in the queue view.
- [x] #3 Tests or a focused manual check confirm queue failures appear in copied diagnostics without leaking sensitive values.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
The action-path errors (cancel/reset/delete/clear/cancelAll) already mirrored to ToastStore (via earlier TASK-387 work); the remaining gap was the QueueActor-emitted `.queueError` event, which only set the in-view banner. AC#3 no-leak: ToastStore.recentErrors is rendered through DiagnosticsRedactor in DebugTab.buildDiagnosticsText, and DiagnosticsRedactorTests.testRedactsFilePaths already covers the exact `...Application Support/Jobhunt/jobhunt.store` shape a queueError carries (plus tokens/keys/query strings). Manual check for the "appears in diagnostics" half (LLMQueueView is a SwiftUI view, not unit-testable without a graphical session): force a queue read error (e.g. with the queue view open), confirm the red banner shows AND Settings → Debug → Copy Diagnostics includes the error under Recent Errors with any path/token redacted.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Routed QueueActor `.queueError` events through `toastStore.show(_:isError:)` in addition to the in-view `errorMessage` banner, so queue operational failures (store read/record errors) now land in `ToastStore.recentErrors` — the same stream Copy Diagnostics reads — instead of being dropped. The banner remains (AC#2). No-leak (AC#3) is inherited: DebugTab redacts every recentErrors message via DiagnosticsRedactor on copy, and DiagnosticsRedactorTests already covers the store-path/bearer/api-key/query-string shapes these messages can contain. App builds; existing redactor tests green. The other queue-action error paths were already mirrored to ToastStore by prior work.
<!-- SECTION:FINAL_SUMMARY:END -->
