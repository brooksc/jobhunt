---
id: TASK-214
title: 'Sidebar: Replace all-jobs badge recomputation with aggregate counts'
status: Done
assignee: []
created_date: '2026-06-12 00:42'
updated_date: '2026-06-12 02:00'
labels:
  - performance
  - sidebar
  - swiftui
  - audit
dependencies: []
references:
  - app/Shell/Sidebar.swift
  - core/Models/SavedSearch.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Sidebar loads all jobs and recomputes badge counts for every status and saved search on refresh. Saved searches make this jobs × searches work as the dataset grows.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Status badge counts no longer require filtering the full jobs array for each status on every render.
- [ ] #2 Saved-search badge counts are cached, query-backed, or computed asynchronously for large datasets.
- [ ] #3 Tests cover count correctness for status and saved-search badge projections.
<!-- AC:END -->
