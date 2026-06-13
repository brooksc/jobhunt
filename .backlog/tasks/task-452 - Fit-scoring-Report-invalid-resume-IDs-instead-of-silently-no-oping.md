---
id: TASK-452
title: 'Fit scoring: Report invalid resume IDs instead of silently no-oping'
status: To Do
assignee: []
created_date: '2026-06-13 19:12'
labels:
  - llm
  - fit-scoring
  - ux
dependencies: []
references:
  - core/LLM/QueueActor.swift
  - tests/CoreTests/JobServiceTests.swift
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`QueueActor.enqueueFit` returns without creating requests when the requested resume ID does not exist. That behavior is currently covered by tests, but it gives callers and users no explanation when fit scoring does nothing. Invalid resume IDs should produce a typed, user-visible failure at the service/UI boundary.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Calling fit enqueue with a missing resume ID produces an explicit typed error or observable user-facing failure state.
- [ ] #2 No fit `LLMRequest` rows are created for an invalid resume ID.
- [ ] #3 Valid fit enqueue behavior is unchanged for existing resumes.
- [ ] #4 Tests cover both invalid-resume and valid-resume enqueue behavior with the new error contract.
<!-- AC:END -->
