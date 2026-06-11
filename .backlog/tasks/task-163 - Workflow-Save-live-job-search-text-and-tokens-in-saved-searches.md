---
id: TASK-163
title: 'Workflow: Save live job search text and tokens in saved searches'
status: Done
assignee: []
created_date: '2026-06-11 20:56'
updated_date: '2026-06-11 21:35'
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

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Passed live `searchText` and `searchTokens` into `SaveSearchSheet`. Added `merged` computed property that starts from `filterState`, overrides `searchText` with the live value, and folds all token-based filters (status, remoteType, minFitScore, minSalary, minRating, recentDays) into the filter state. Both `buildChips()` (preview) and `save()` now use `merged` so the saved search captures everything visible in the search bar.
<!-- SECTION:FINAL_SUMMARY:END -->
