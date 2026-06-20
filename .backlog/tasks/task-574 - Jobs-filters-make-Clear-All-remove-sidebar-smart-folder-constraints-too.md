---
id: TASK-574
title: 'Jobs filters: make Clear All remove sidebar smart-folder constraints too'
status: To Do
assignee: []
created_date: '2026-06-20 05:13'
labels:
  - audit
  - jobs
  - filters
  - workflow
dependencies: []
modified_files:
  - app/Views/Jobs/JobsView.swift
  - app/Shell/Sidebar.swift
  - tests/AppUITests/BehaviorUITests.swift
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: `JobsView.clearAllFilters()` clears search tokens, text, `filterState`, and `router.activeSavedSearchID`, but it does not clear `router.sidebarJobFilter` or the `localSidebarFilter` mirror. The active filters bar always shows a `Clear All` button even when the current constraint is a sidebar smart-folder status, but clicking it leaves the status filter in place.

Why it matters: The UI promises to clear all visible constraints but leaves one of the strongest constraints active. Users can remain stuck in a status smart folder while the filter bar implies cleanup happened, and future filter work has to remember that sidebar filters are managed outside the same clear path.

Suggested implementation: Update `clearAllFilters()` to clear `router.sidebarJobFilter` as well as `localSidebarFilter`, and ensure sidebar selection sync returns to All Jobs when clearing from the Jobs view. Add a focused UI/unit regression around Clear All from a status-filtered view with no other filters and with mixed filters.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Clicking Clear All while viewing a sidebar status smart folder returns the Jobs list to All Jobs.
- [ ] #2 Clicking Clear All with sidebar status plus search/filter constraints clears every visible constraint in one action.
- [ ] #3 The active filters bar no longer remains visible solely because `localSidebarFilter` is stale after Clear All.
- [ ] #4 Regression coverage verifies `router.sidebarJobFilter` is nil after Clear All.
<!-- AC:END -->
