---
id: TASK-451
title: 'LLM queue: Surface fetch failures instead of reporting an empty queue'
status: To Do
assignee: []
created_date: '2026-06-13 19:10'
labels:
  - bug
  - llm
  - queue
  - observability
dependencies: []
references:
  - core/LLM/QueueActor.swift
  - app/Views/Queue/LLMQueueView.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`QueueActor.fetchQueuedRequests` catches any store fetch error and returns an empty array. The processing loop then emits a normal completion event, making storage/query failures look like there is no work. Queue fetch failures should be visible to the UI or logs and should not be reported as successful empty completion.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A store fetch failure while reading queued LLM requests produces an observable queue error state or event.
- [ ] #2 The queue does not emit a misleading successful empty completion for fetch failures.
- [ ] #3 Existing successful empty-queue behavior remains unchanged when there are genuinely no queued requests.
- [ ] #4 Focused tests cover fetch failure handling and normal empty-queue handling.
<!-- AC:END -->
