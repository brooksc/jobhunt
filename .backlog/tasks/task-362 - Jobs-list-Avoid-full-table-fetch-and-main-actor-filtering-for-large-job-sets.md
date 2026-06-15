---
id: TASK-362
title: 'Jobs list: Avoid full-table fetch and main-actor filtering for large job sets'
status: Done
assignee: []
created_date: '2026-06-12 22:03'
updated_date: '2026-06-15 19:39'
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

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Closed as not-needed-at-scale. Expected data is a few hundred jobs (one user's tracked applications), at which the existing approach is already more than sufficient: JobsView caches the filter+sort result (`cachedFilteredJobs`, computed once per actual input change, not per render) and SwiftUI `List` already windows row rendering. Dynamic enum/free-text filters can't be pushed into SwiftData predicates (same limitation documented in TASK-366), and an off-main rewrite of the primary screen would add complexity/stale-window risk for benefit only at scales this app won't reach. Per maintainer guidance, no further optimization is warranted; added a CLAUDE.md convention ("Don't over-optimize for scale this app won't reach") to prevent similar speculative perf work without a measured problem.
<!-- SECTION:FINAL_SUMMARY:END -->
