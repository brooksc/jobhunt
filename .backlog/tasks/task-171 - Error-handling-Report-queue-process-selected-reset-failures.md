---
id: TASK-171
title: 'Error handling: Report queue process-selected reset failures'
status: Done
assignee: []
created_date: '2026-06-11 21:44'
updated_date: '2026-06-11 22:20'
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

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Fixed `LLMQueueView.processSelected(_:)` to use do/catch instead of `try?`. Reset failures set `errorMessage` (the same local banner already used by cancel/reset/delete). Processing only starts if at least one reset succeeded, preventing ambiguous partial-reset states. Now consistent with the other queue command handlers.
<!-- SECTION:FINAL_SUMMARY:END -->
