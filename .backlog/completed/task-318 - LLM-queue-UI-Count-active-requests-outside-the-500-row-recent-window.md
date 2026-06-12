---
id: TASK-318
title: 'LLM queue UI: Count active requests outside the 500-row recent window'
status: Done
assignee: []
created_date: '2026-06-12 19:41'
updated_date: '2026-06-12 20:03'
labels:
  - audit
  - llm-queue
  - ui
dependencies: []
references:
  - app/Views/Queue/LLMQueueView.swift
  - app/Views/Queue/QueueSummaryBar.swift
  - core/LLM/QueueActor.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
LLMQueueView fetches the 500 newest requests and assumes active requests are always newest. Requeued launch-time requests keep old createdAt values, so active work can be hidden by newer terminal history.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Queue summary counts queued/running/failed requests accurately regardless of the recent-history window.
- [ ] #2 The visible queue provides an explicit way to surface active requests even when older than recent terminal rows.
- [ ] #3 Tests or extracted query logic cover old requeued active requests plus many newer terminal rows.
<!-- AC:END -->
