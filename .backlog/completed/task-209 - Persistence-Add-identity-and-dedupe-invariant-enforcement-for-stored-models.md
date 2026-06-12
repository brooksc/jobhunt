---
id: TASK-209
title: 'Persistence: Add identity and dedupe invariant enforcement for stored models'
status: Done
assignee: []
created_date: '2026-06-12 00:38'
updated_date: '2026-06-12 01:12'
labels:
  - persistence
  - data-integrity
  - swiftdata
  - audit
dependencies: []
references:
  - core/Models/Capture.swift
  - core/Models/Job.swift
  - core/Services/BackgroundStore.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Core identity and dedupe fields such as Capture.id, Capture.rawHash, Job.id, and Job.jobNumber are plain stored properties. Normal service paths dedupe before insertion, but direct writes, imports, or future code can create duplicate identities.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Supported unique constraints are added for identity fields, or writes are centralized behind invariant-checking store APIs.
- [x] #2 Migration/import paths handle existing duplicates deterministically before constraints are applied.
- [x] #3 Tests cover duplicate identity/dedupe attempts through service and import/store paths.
<!-- AC:END -->
