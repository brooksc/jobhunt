---
id: TASK-364
title: >-
  Sidebar: Cache or query saved-search counts without scanning all jobs per
  search
status: Done
assignee: []
created_date: '2026-06-12 22:03'
updated_date: '2026-06-15 19:20'
labels:
  - audit
  - performance
  - sidebar
  - saved-search
dependencies: []
references:
  - app/Shell/Sidebar.swift
  - core/Models/SavedSearch.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Sidebar computes each saved-search badge by scanning allJobs, making render cost proportional to jobs times saved searches.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Saved-search badge counts are cached, debounced, or computed through a service/projection layer.
- [x] #2 Sidebar remains responsive with many saved searches and a large job set.
- [x] #3 A focused test or documented manual scenario covers count correctness after job/status/search changes.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Moved sidebar badge counts off the synchronous render path. Extracted a Sendable projection in JobhuntCore — `JobMatchFields` (the exact Job fields a saved-search filter reads) and `SavedSearchCriteria` (the filter predicate with an injected `now`); `SavedSearch.matches` now delegates to it (one source of truth; existing SavedSearchMatchesTests regression-cover the delegation). Sidebar status + saved-search counts are now `@State` recomputed off-main in `.task(id: countsRefreshID)`, debounced via SwiftUI task restart. The refresh signal is built from the same JobMatchFields/criteria snapshots, so counts re-run exactly when something that could change a badge changes — no field-list drift, no stale badges. A `!Task.isCancelled` guard stops a superseded refresh from publishing stale counts (TASK-384 hazard). Main-thread body work drops from O(N×S) to O(N). AC#3: SavedSearchCriteriaTests cover count correctness after status/field/criteria changes, recentDays determinism, text/jobNumber matching, and snapshot equality/hash stability. Full fast gate green; app builds.
<!-- SECTION:FINAL_SUMMARY:END -->
