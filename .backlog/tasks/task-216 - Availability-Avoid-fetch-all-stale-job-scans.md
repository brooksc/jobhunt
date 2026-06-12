---
id: TASK-216
title: 'Availability: Avoid fetch-all stale job scans'
status: To Do
assignee: []
created_date: '2026-06-12 00:42'
labels:
  - performance
  - availability
  - swiftdata
  - audit
dependencies: []
references:
  - core/Services/AvailabilityChecker.swift
  - core/Models/Job.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
AvailabilityChecker.fetches all jobs sorted by creation date, filters status and capture age in memory, then applies the limit. Large histories make a small stale check increasingly expensive.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Stale availability checks can apply limits before loading the entire job history.
- [ ] #2 If SwiftData relationship predicates are insufficient, a denormalized queryable date/status field is introduced and maintained.
- [ ] #3 Tests cover stale-check correctness with many archived/closed jobs before eligible active jobs.
<!-- AC:END -->
