---
id: TASK-145
title: 'Performance: Make LLM queue processing and bulk mutations batch-oriented'
status: To Do
assignee: []
created_date: '2026-06-11 03:45'
labels:
  - performance
  - queue
  - swiftdata
dependencies: []
references:
  - core/LLM/QueueActor.swift
  - core/Services/JobService.swift
  - core/Services/BackgroundStore.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Performance audit finding: queue processing fetches all LLM requests each batch and filters queued requests in memory; enqueue and bulk job operations often perform one fetch/save per row or whole-table updates.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Queue processing fetches only queued work using predicate-friendly status/type fields and `fetchLimit`.
- [ ] #2 Bulk enqueue, bulk status, bulk extraction reset, and mark-expired operations fetch target records in batches and save once per operation where practical.
- [ ] #3 Old succeeded/failed queue history is pruned, archived, or paged so current processing is independent of total history size.
- [ ] #4 Tests cover bulk operations for correctness and reduced save/query behavior.
<!-- AC:END -->
