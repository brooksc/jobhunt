---
id: TASK-285
title: 'Saved searches: Restore saved sort settings when selected'
status: Done
assignee: []
created_date: '2026-06-12 03:44'
updated_date: '2026-06-12 04:46'
labels:
  - audit
  - saved-search
  - search
  - sorting
dependencies: []
references:
  - core/Models/SavedSearch.swift
  - app/Views/Jobs/JobsFilterState.swift
  - app/Views/Jobs/JobsView.swift
modified_files:
  - app/Views/Jobs/JobsView.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
SavedSearch persists sortKeyRaw and sortAscending, and saving includes the current sort, but applying a saved search only rebuilds tokens/search text. Restore the saved sort key and direction when the saved search is opened.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Selecting a saved search applies its saved sortKeyRaw and sortAscending values.
- [x] #2 Saved search UI indicates the active sort after selection.
- [x] #3 Tests cover saving a non-default sort and restoring it.
<!-- AC:END -->
