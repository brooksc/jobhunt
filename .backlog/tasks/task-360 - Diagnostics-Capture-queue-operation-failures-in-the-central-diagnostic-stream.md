---
id: TASK-360
title: 'Diagnostics: Capture queue operation failures in the central diagnostic stream'
status: To Do
assignee: []
created_date: '2026-06-12 21:48'
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
- [ ] #1 Queue operation failures are recorded in the same diagnostic/error stream used by the Debug tab.
- [ ] #2 User-facing queue errors remain visible in the queue view.
- [ ] #3 Tests or a focused manual check confirm queue failures appear in copied diagnostics without leaking sensitive values.
<!-- AC:END -->
