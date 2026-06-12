---
id: TASK-215
title: 'Jobs: Introduce query-backed or paged filtering for large job lists'
status: To Do
assignee: []
created_date: '2026-06-12 00:42'
labels:
  - performance
  - jobs
  - swiftui
  - swiftdata
  - audit
dependencies: []
references:
  - app/Views/Jobs/JobsView.swift
  - app/Views/Jobs/JobsSortLogic.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
JobsView loads all jobs and performs search, filter, selected-ID synchronization, and sorting in memory. The filteredJobs computation is reused by other computed properties, doubling work on some changes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Common filters such as status/date/sort are pushed into SwiftData queries or a bounded projection layer where practical.
- [ ] #2 filteredJobIDs avoids recomputing the full filtered/sorted list unnecessarily.
- [ ] #3 Large-list UI behavior is covered by performance-oriented tests or benchmarks.
<!-- AC:END -->
