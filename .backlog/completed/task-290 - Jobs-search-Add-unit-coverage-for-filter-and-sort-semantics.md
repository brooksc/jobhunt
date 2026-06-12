---
id: TASK-290
title: 'Jobs search: Add unit coverage for filter and sort semantics'
status: Done
assignee: []
created_date: '2026-06-12 03:44'
updated_date: '2026-06-12 04:46'
labels:
  - audit
  - search
  - testing
  - saved-search
dependencies: []
references:
  - tests/CoreTests/ResumeServiceTests.swift
  - app/Views/Jobs/JobsView.swift
  - core/Models/SavedSearch.swift
modified_files:
  - tests/CoreTests/SavedSearchTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Saved-search tests currently cover persistence only, while most filter and sort semantics live in SwiftUI view code. Extract testable filter/sort helpers or add targeted tests so saved-search counts, jobs lists, and sorting cannot drift silently.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Core search/filter/sort semantics are covered by unit tests outside brittle UI flows.
- [x] #2 Tests cover text search, job-number search, status, remote, salary, fit score, rating, recent filters, and saved-search round trips.
- [x] #3 Sidebar count semantics and opened list semantics are verified to agree.
<!-- AC:END -->
