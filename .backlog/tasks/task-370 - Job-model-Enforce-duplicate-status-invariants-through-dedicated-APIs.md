---
id: TASK-370
title: 'Job model: Enforce duplicate status invariants through dedicated APIs'
status: To Do
assignee: []
created_date: '2026-06-12 22:26'
labels:
  - audit
  - data-model
  - invariants
  - duplicates
dependencies: []
references:
  - core/Models/Job.swift
  - core/Services/JobService.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Job documents duplicateOfJobID != nil as requiring status == .duplicate, but generic status and field update paths can change duplicateOfJobID or status independently and create inconsistent rows.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Introduce dedicated markDuplicate/clearDuplicate or invariant-repair APIs for duplicate state changes.
- [ ] #2 Generic job update/status paths preserve or repair duplicate invariants consistently.
- [ ] #3 Tests cover setting status on duplicate jobs, clearing duplicateOfJobID, and marking duplicates through supported APIs.
<!-- AC:END -->
