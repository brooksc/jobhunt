---
id: TASK-362
title: 'Jobs list: Avoid full-table fetch and main-actor filtering for large job sets'
status: To Do
assignee: []
created_date: '2026-06-12 22:03'
labels:
  - audit
  - performance
  - swiftdata
  - jobs
dependencies: []
references:
  - app/Views/Jobs/JobsView.swift
  - app/Views/Jobs/JobsSortLogic.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
JobsView materializes every Job and recomputes filter/search/sort in memory on job changes and every search/filter change. This will degrade as captured job history grows.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Common JobsView filters and sorts are pushed into bounded SwiftData queries where possible.
- [ ] #2 The jobs list has a pagination/windowing strategy or measured acceptable behavior for large datasets.
- [ ] #3 Large-dataset UI performance is covered by a focused benchmark, test fixture, or documented manual smoke check.
<!-- AC:END -->
