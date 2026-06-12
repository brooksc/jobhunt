---
id: TASK-269
title: 'LLM: Make extracted typed fields reflect latest extraction result'
status: To Do
assignee: []
created_date: '2026-06-12 03:26'
labels:
  - audit
  - llm
  - persistence
  - data-consistency
dependencies: []
references:
  - core/LLM/QueueActor.swift
  - core/Services/JobService.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Queue writeback stores new extractedJSON but preserves old scalar values whenever the latest extraction returns nil. This can make typed fields disagree with extractedJSON during non-reset reprocessing. Decide ownership rules for extracted fields and overwrite extracted-owned typed fields with the latest result, including nil, while preserving true manual edits separately if needed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A re-extraction that returns null for an extracted-owned field clears that typed field instead of preserving stale data.
- [ ] #2 Manual user edits, if supported for the same fields, have an explicit precedence model and tests.
- [ ] #3 QueueActor tests verify extractedJSON and typed fields stay consistent after reprocessing.
<!-- AC:END -->
