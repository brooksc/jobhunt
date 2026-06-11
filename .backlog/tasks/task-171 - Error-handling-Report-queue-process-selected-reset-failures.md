---
id: TASK-171
title: 'Error handling: Report queue process-selected reset failures'
status: To Do
assignee: []
created_date: '2026-06-11 21:44'
labels:
  - audit
  - error-handling
  - llm-queue
dependencies: []
references:
  - app/Views/Queue/LLMQueueView.swift
  - core/LLM/QueueActor.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`LLMQueueView.processSelected` resets selected queue items with `try?` and then starts processing. If any reset fails, the failure is invisible and processing still starts, while adjacent queue actions already report cancel/reset errors. Make process-selected follow the same error reporting and partial-failure behavior as the other queue commands.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Reset failures during process-selected are reported to the user.
- [ ] #2 Processing does not start under an ambiguous partial-reset state, or the partial behavior is explicitly communicated.
- [ ] #3 Queue command error handling is consistent across process, reset, cancel, and delete actions.
<!-- AC:END -->
