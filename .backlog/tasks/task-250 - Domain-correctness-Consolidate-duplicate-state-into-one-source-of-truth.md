---
id: TASK-250
title: 'Domain correctness: Consolidate duplicate state into one source of truth'
status: To Do
assignee: []
created_date: '2026-06-12 02:41'
labels:
  - audit
  - domain
  - duplicates
dependencies: []
references:
  - core/Models/Job.swift
  - core/Services/BackgroundStore.swift
  - app/Views/Quality/DataQualityView.swift
  - app/Shell/Sidebar.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The job domain currently represents duplicate state both as `Job.status == .duplicate` and as `Job.duplicateOfJobID != nil`. Ingested semantic duplicates set `duplicateOfJobID` while leaving status at the default `.new`, and different screens/services filter on different signals. This can let duplicates appear in normal workflows, make sidebar counts disagree, and leave the domain without a clear invariant.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Duplicate state has a documented canonical representation or a documented synchronization invariant.
- [ ] #2 Semantic duplicate ingest, manual duplicate marking, unmarking, list filtering, sidebar badges, and data quality filtering all use the same invariant.
- [ ] #3 Regression tests cover semantic duplicate ingest and visibility in normal job lists/data quality views.
<!-- AC:END -->
