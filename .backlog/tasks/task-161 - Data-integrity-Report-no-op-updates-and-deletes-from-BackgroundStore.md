---
id: TASK-161
title: 'Data integrity: Report no-op updates and deletes from BackgroundStore'
status: To Do
assignee: []
created_date: '2026-06-11 20:56'
labels:
  - audit
  - data-integrity
  - service-contract
dependencies: []
references:
  - core/Services/BackgroundStore.swift
  - core/Services/JobService.swift
  - core/Services/SiteService.swift
  - core/Services/ResumeService.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`BackgroundStore.update` and `BackgroundStore.delete` save successfully even when no rows match. Service methods that target a specific ID therefore cannot tell success from a stale ID, including job actions, site state changes, and job deletes. Return affected counts or add updateOne/deleteOne helpers, then update services that should throw not-found errors.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Store APIs used for single-record mutations can report zero matches.
- [ ] #2 Services that target a required ID throw or return an explicit not-found result when no row is affected.
- [ ] #3 Tests cover at least job action completion, site state update, and job deletion for missing IDs.
<!-- AC:END -->
