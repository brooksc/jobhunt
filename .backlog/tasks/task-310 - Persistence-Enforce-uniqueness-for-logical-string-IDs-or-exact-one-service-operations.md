---
id: TASK-310
title: >-
  Persistence: Enforce uniqueness for logical string IDs or exact-one service
  operations
status: To Do
assignee: []
created_date: '2026-06-12 19:34'
labels:
  - audit
  - persistence
  - data-integrity
dependencies: []
references:
  - core/Models/Job.swift
  - core/Models/SavedSearch.swift
  - core/Services/JobService.swift
  - core/Services/BackgroundStore.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Several externally used IDs such as Job.id, Resume.id, LLMRequest.id, Contact.id, and SiteReview.id are plain stored strings, while some services query by these IDs and mutate all matches. Duplicate logical IDs remain structurally possible through imports or direct writes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Define which logical string IDs must be unique at the model level versus enforced by service boundaries.
- [ ] #2 Add uniqueness constraints or exact-one update/delete paths for service operations that target logical IDs.
- [ ] #3 File-backed tests prove duplicate logical IDs cannot cause broad unintended mutations for critical models.
<!-- AC:END -->
