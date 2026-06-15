---
id: TASK-371
title: 'Schema performance: Add predicate-friendly raw fields for status-like enums'
status: Done
assignee: []
created_date: '2026-06-12 22:26'
updated_date: '2026-06-15 19:40'
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

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Closed as not-needed-at-scale (maintainer guidance; see CLAUDE.md "Don't over-optimize for scale this app won't reach"). The proposed denormalized raw-status columns would require a Job/LLMRequest schema change + migration + backfill — exactly the migration risk deliberately avoided in TASK-366 — purely to enable predicate filtering that is unnecessary at the real scale (a few hundred rows), where full-fetch + in-memory enum filtering is imperceptible. The one genuinely unbounded path (MCP status-filtered listing) was already bounded in TASK-366 via cursor paging without any schema change. Revisit only if a measured problem appears at much larger scale or a SchemaV2 change (TASK-480) makes raw fields free to add.
<!-- SECTION:FINAL_SUMMARY:END -->
