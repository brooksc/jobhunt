---
id: TASK-361
title: 'LLM queue: Make Process All behavior observable and consistent'
status: To Do
assignee: []
created_date: '2026-06-12 21:48'
labels:
  - audit
  - ux
  - llm-queue
dependencies: []
references:
  - app/Views/Queue/LLMQueueView.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
processAll() claims to enqueue pending jobs but only starts processing when existing queued requests are present. If no queued requests exist it silently does nothing, leaving users without feedback.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Process All either enqueues eligible pending jobs or is renamed/changed to match its actual behavior.
- [ ] #2 The UI provides clear feedback when there is nothing to process.
- [ ] #3 A focused test or manual verification covers the no-op case and the queued-request case.
<!-- AC:END -->
