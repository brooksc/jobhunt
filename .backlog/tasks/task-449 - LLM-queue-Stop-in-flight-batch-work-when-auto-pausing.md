---
id: TASK-449
title: 'LLM queue: Stop in-flight batch work when auto-pausing'
status: To Do
assignee: []
created_date: '2026-06-13 19:08'
labels:
  - bug
  - llm
  - queue
dependencies: []
references:
  - core/LLM/QueueActor.swift
  - tests/CoreTests/ExtractionEngineTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`QueueActor.startProcessing` launches a provider-concurrency batch before observing failures. When the auto-pause threshold is reached, it pauses and breaks from result handling, but already-started sibling tasks can continue provider calls. Auto-pause should prevent additional cloud cost beyond the requests that must finish, or explicitly cancel remaining batch work.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 When auto-pause triggers, no additional queued requests from the same batch begin provider execution after the pause decision.
- [ ] #2 Already-started tasks either observe cancellation before calling the provider or are intentionally allowed to finish with documented behavior.
- [ ] #3 Queue completion accounting remains accurate after auto-pause cancellation or early stop.
- [ ] #4 Focused tests cover auto-pause behavior with a provider concurrency limit greater than one.
<!-- AC:END -->
