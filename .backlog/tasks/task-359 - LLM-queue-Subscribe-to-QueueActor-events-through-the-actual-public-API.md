---
id: TASK-359
title: 'LLM queue: Subscribe to QueueActor events through the actual public API'
status: Done
assignee: []
created_date: '2026-06-12 21:48'
updated_date: '2026-06-15 05:43'
labels:
  - audit
  - bug
  - llm-queue
dependencies: []
references:
  - app/Views/Queue/LLMQueueView.swift
  - core/LLM/QueueActor.swift
modified_files:
  - app/Views/Queue/LLMQueueView.swift
  - app/Platform/PlatformIntegration.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
LLMQueueView awaits queueActor.events, but QueueActor exposes subscribe() and no events property is present in the repo. This can break compilation or event delivery depending on current build state.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 LLMQueueView consumes queue events via QueueActor.subscribe() or QueueActor exposes a documented events stream.
- [x] #2 Queue event handling still updates pause state and user notifications correctly.
- [x] #3 A compile or focused UI/build check covers the queue view.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Already resolved in current code: both LLMQueueView (handleQueueEvent loop) and PlatformIntegration consume queue events via `QueueActor.subscribe()` — there is no `.events` property anywhere in the repo (grep confirms). LLMQueueView updates pause state on .autoPaused and PlatformIntegration posts the auto-pause notification (AC#2). AC#3: covered by the app target building cleanly (verified this session). No code change required beyond confirming the current state; closed as done.
<!-- SECTION:FINAL_SUMMARY:END -->
