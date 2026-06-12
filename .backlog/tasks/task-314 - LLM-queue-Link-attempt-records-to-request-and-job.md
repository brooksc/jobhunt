---
id: TASK-314
title: 'LLM queue: Link attempt records to request and job'
status: To Do
assignee: []
created_date: '2026-06-12 19:38'
labels:
  - audit
  - llm-queue
  - history
dependencies: []
references:
  - core/Models/LLMRequest.swift
  - core/Models/LLMRequestAttempt.swift
  - core/LLM/QueueActor.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
LLMRequestAttempt rows are inserted without setting attempt.request or attempt.job. Request detail history is empty, pruning/deleting requests can leave orphan attempts, and queue history cannot reliably explain what happened to a request.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every extraction and fit attempt record is linked to its LLMRequest and Job before saving.
- [ ] #2 Deleting or pruning a request cascades to its attempt history as intended.
- [ ] #3 Tests verify request.attempts contains success and failure attempts and no orphan attempts remain after request deletion.
<!-- AC:END -->
