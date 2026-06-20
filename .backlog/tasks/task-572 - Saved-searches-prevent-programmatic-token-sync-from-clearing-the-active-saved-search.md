---
id: TASK-572
title: >-
  Saved searches: prevent programmatic token sync from clearing the active saved
  search
status: To Do
assignee: []
created_date: '2026-06-20 05:10'
labels:
  - audit
  - saved-searches
  - jobs
  - workflow
dependencies: []
modified_files:
  - app/Views/Jobs/JobsView.swift
  - app/Views/Jobs/JobsFilterState.swift
  - tests/CoreTests/SavedSearchTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: Selecting a saved search sets `router.activeSavedSearchID`, and `JobsView` responds by calling `applySearchToTokens(_:)`, which assigns `searchTokens` from the saved search. A separate `.onChange(of: searchTokens)` then unconditionally sets `router.activeSavedSearchID = nil`. That means applying a saved search can immediately make the app treat it as an ad hoc token search instead of an active saved search. `applySearchToTokens` also updates only tokens/text/sort and does not reset the rest of `filterState`, so prior session-only filters such as `extractionFilter` or `meetsCriteriaOnly` can continue narrowing the result set.

Why it matters: Saved searches become a leaky UI state transition rather than a stable navigation state. The sidebar selection/title/chip can fall out of sync with what the user clicked, and stale filters can make a saved search appear to return too few jobs. This is Change Propagation/Information Leakage: the saved-search concept is split between router state, search tokens, and ad hoc filter state with no single owner for programmatic vs user edits.

Suggested implementation: Replace `applySearchToTokens` with a single `applySavedSearch` path that resets the full filter state first, applies saved criteria atomically, and suppresses the token-change observer while the update is programmatic. Alternatively, represent saved-search criteria directly in `JobsFilterState` and derive tokens purely as a view of that state. Add regression coverage around selecting a saved search after advanced filters are active.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Selecting a saved search leaves `router.activeSavedSearchID` set to that search until the user explicitly edits/clears filters or selects another sidebar item.
- [ ] #2 Applying a saved search clears prior non-saved session filters such as extraction status and meets-criteria-only.
- [ ] #3 User-initiated token edits still clear the active saved search.
- [ ] #4 Regression tests or UI-level coverage exercise saved-search selection after an existing token filter and after an advanced session-only filter.
<!-- AC:END -->
