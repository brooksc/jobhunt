---
id: TASK-163
title: 'Workflow: Save live job search text and tokens in saved searches'
status: To Do
assignee: []
created_date: '2026-06-11 20:56'
labels:
  - audit
  - workflow
  - saved-search
dependencies: []
references:
  - app/Views/Jobs/JobsView.swift
  - app/Views/Jobs/JobsFilterState.swift
  - app/Views/Jobs/SaveSearchSheet.swift
  - core/Models/SavedSearch.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`JobsView` owns the active `.searchable` text and search tokens separately from `JobsFilterState`, but `SaveSearchSheet` receives only `filterState`. As a result, saved searches can miss the user’s live free-text query and token filters even though applying a saved search can restore text/tokens. Use one source of truth or pass the live search state into the saved-search conversion.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Saving a search with free-text query preserves that query after reload/apply.
- [ ] #2 Saving a search with search tokens preserves equivalent filter behavior after reload/apply.
- [ ] #3 The save/search state has a clear single source of truth or explicit mapping tests.
<!-- AC:END -->
