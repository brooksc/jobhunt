---
id: TASK-211
title: 'Queue: Prevent LLM processing starvation behind old request history'
status: Done
assignee: []
created_date: '2026-06-12 00:41'
updated_date: '2026-06-12 02:00'
labels:
  - performance
  - queue
  - llm
  - reliability
  - audit
dependencies: []
references:
  - core/LLM/QueueActor.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
QueueActor fetches the oldest 1,000 LLMRequest rows, filters queued requests in memory, and exits when none are found. If queued work sits behind recent terminal history outside that fixed window, processing can stop even though work exists.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Queued request lookup cannot miss queued work because of terminal history ordering.
- [ ] #2 Queue processing either uses a queryable status path, bounded paging until queued rows are found, or a maintained pending index.
- [ ] #3 Tests cover more than 1,000 older non-queued requests followed by queued requests.
<!-- AC:END -->
