---
id: TASK-371
title: 'Schema performance: Add predicate-friendly raw fields for status-like enums'
status: To Do
assignee: []
created_date: '2026-06-12 22:26'
labels:
  - audit
  - schema
  - performance
  - swiftdata
dependencies: []
references:
  - core/Models/Enums.swift
  - core/Services/JobService.swift
  - core/LLM/QueueActor.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Status-like enum fields are stored as Swift enums, and multiple code paths fall back to full fetch plus in-memory filtering because SwiftData predicates cannot compare those enum cases efficiently.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Add a schema strategy for predicate-friendly raw status fields or equivalent indexed/queryable projections.
- [ ] #2 Job, LLMRequest, and other status-heavy queries use bounded predicates instead of full-table enum filtering where practical.
- [ ] #3 Migration/backfill tests verify raw fields stay consistent with enum-facing APIs.
<!-- AC:END -->
