---
id: TASK-359
title: 'LLM queue: Subscribe to QueueActor events through the actual public API'
status: To Do
assignee: []
created_date: '2026-06-12 21:48'
labels:
  - audit
  - bug
  - llm-queue
dependencies: []
references:
  - app/Views/Queue/LLMQueueView.swift
  - core/LLM/QueueActor.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
LLMQueueView awaits queueActor.events, but QueueActor exposes subscribe() and no events property is present in the repo. This can break compilation or event delivery depending on current build state.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 LLMQueueView consumes queue events via QueueActor.subscribe() or QueueActor exposes a documented events stream.
- [ ] #2 Queue event handling still updates pause state and user notifications correctly.
- [ ] #3 A compile or focused UI/build check covers the queue view.
<!-- AC:END -->
