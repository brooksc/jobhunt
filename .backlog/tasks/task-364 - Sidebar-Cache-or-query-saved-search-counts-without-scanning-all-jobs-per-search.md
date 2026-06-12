---
id: TASK-364
title: >-
  Sidebar: Cache or query saved-search counts without scanning all jobs per
  search
status: To Do
assignee: []
created_date: '2026-06-12 22:03'
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
- [ ] #1 Saved-search badge counts are cached, debounced, or computed through a service/projection layer.
- [ ] #2 Sidebar remains responsive with many saved searches and a large job set.
- [ ] #3 A focused test or documented manual scenario covers count correctness after job/status/search changes.
<!-- AC:END -->
