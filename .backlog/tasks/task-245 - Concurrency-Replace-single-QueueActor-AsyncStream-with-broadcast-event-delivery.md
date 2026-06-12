---
id: TASK-245
title: >-
  Concurrency: Replace single QueueActor AsyncStream with broadcast event
  delivery
status: Done
assignee: []
created_date: '2026-06-12 02:18'
updated_date: '2026-06-12 02:25'
labels:
  - concurrency
  - queue
  - macos
dependencies: []
references:
  - core/LLM/QueueActor.swift
  - app/Platform/PlatformIntegration.swift
  - app/Views/Queue/LLMQueueView.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
QueueActor exposes one AsyncStream that is consumed by both PlatformIntegration and LLMQueueView. AsyncStream is not a broadcast mechanism, so queue events can be split between consumers or missed. Introduce fan-out delivery so each subscriber receives all queue events it needs.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Queue event delivery supports multiple independent subscribers without event stealing.
- [ ] #2 PlatformIntegration and LLMQueueView each receive auto-pause and processing-complete events reliably.
- [ ] #3 Subscriber lifecycle is managed so dismissed views do not leak continuations.
- [ ] #4 Tests cover two subscribers receiving the same emitted event.
<!-- AC:END -->
