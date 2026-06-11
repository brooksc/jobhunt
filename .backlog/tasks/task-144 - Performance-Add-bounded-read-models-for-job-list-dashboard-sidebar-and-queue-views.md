---
id: TASK-144
title: >-
  Performance: Add bounded read models for job list, dashboard, sidebar, and
  queue views
status: To Do
assignee: []
created_date: '2026-06-11 03:45'
labels:
  - performance
  - swiftui
  - swiftdata
dependencies: []
references:
  - app/Views/Jobs/JobsView.swift
  - app/Views/Dashboard/DashboardView.swift
  - app/Shell/Sidebar.swift
  - app/Views/Queue/LLMQueueView.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Performance audit finding: major SwiftUI screens load full SwiftData tables and perform filtering, sorting, counts, saved-search matching, and queue filtering in computed properties. This makes UI render cost grow with all jobs, sites, captures, and LLM request history.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Jobs list uses a bounded query/read model with pagination or explicit fetch limits for normal browsing/search.
- [ ] #2 Dashboard and Sidebar use service-produced metrics/counts or `fetchCount`-style bounded queries instead of repeatedly scanning all jobs in view computed properties.
- [ ] #3 LLM Queue view uses bounded slices and status/type filters without loading full request history.
- [ ] #4 Large seeded-data UI tests or performance tests cover initial render and filter/search interactions.
<!-- AC:END -->
