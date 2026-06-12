---
id: TASK-372
title: 'Store opening: Add preflight or migration repair for uniqueness constraints'
status: To Do
assignee: []
created_date: '2026-06-12 22:26'
labels:
  - audit
  - schema
  - migration
  - data-safety
dependencies: []
references:
  - core/Models/Job.swift
  - core/Models/Capture.swift
  - core/Models/ModelContainerFactory.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Several models document that duplicate rows must be removed before opening with unique constraints active, but production container creation opens the store directly. Future uniqueness constraints need a safe preflight or custom migration path.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Document and implement a preflight/custom-migration strategy before adding additional uniqueness constraints to existing fields.
- [ ] #2 Existing unique-constrained fields have a recovery story for stores containing duplicate legacy rows.
- [ ] #3 File-backed tests cover duplicate legacy data and expected repair or recovery behavior.
<!-- AC:END -->
