---
id: TASK-286
title: >-
  Saved searches: Share one filter implementation for sidebar counts and job
  lists
status: Done
assignee: []
created_date: '2026-06-12 03:44'
updated_date: '2026-06-12 04:46'
labels:
  - audit
  - saved-search
  - search
  - data-consistency
dependencies: []
references:
  - core/Models/SavedSearch.swift
  - app/Shell/Sidebar.swift
  - app/Views/Jobs/JobsView.swift
modified_files:
  - core/Models/SavedSearch.swift
  - tests/CoreTests/SavedSearchTests.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Saved-search sidebar counts use SavedSearch.matches while the jobs list uses JobsView.computeFilteredJobs. The implementations already differ, such as job-number text matching. Extract shared filter logic so badges and opened lists agree.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Saved-search badge counts and opened saved-search list counts are computed with the same filter semantics.
- [x] #2 Job-number search behavior is consistent between saved-search counts and lists.
- [x] #3 Unit tests cover SavedSearch/JobsFilterState matching for text, job number, status, remote, salary, fit, rating, and recent filters.
<!-- AC:END -->
