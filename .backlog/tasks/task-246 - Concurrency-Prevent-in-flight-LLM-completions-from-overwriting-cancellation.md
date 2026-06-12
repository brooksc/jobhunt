---
id: TASK-246
title: 'Concurrency: Prevent in-flight LLM completions from overwriting cancellation'
status: Done
assignee: []
created_date: '2026-06-12 02:19'
updated_date: '2026-06-12 02:25'
labels:
  - concurrency
  - queue
  - llm
dependencies: []
references:
  - core/LLM/QueueActor.swift
  - app/Views/Queue/LLMQueueView.swift
  - tests/CoreTests/ExtractionEngineTests.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Queue cancellation only updates request status in the database; the provider task continues and can later mark the same request succeeded. Track in-flight tasks or re-check request status before persisting completion so cancellation remains authoritative.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Cancelling a running request prevents later provider completion from marking it succeeded.
- [ ] #2 Extraction and fit completion paths both verify the request is still running before writing success state.
- [ ] #3 Cancelled requests do not update job extraction/fit fields after cancellation.
- [ ] #4 Tests cover cancellation racing with delayed provider success.
<!-- AC:END -->
