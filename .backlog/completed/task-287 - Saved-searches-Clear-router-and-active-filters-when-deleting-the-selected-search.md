---
id: TASK-287
title: >-
  Saved searches: Clear router and active filters when deleting the selected
  search
status: Done
assignee: []
created_date: '2026-06-12 03:44'
updated_date: '2026-06-12 04:46'
labels:
  - audit
  - saved-search
  - routing
  - ux
dependencies: []
references:
  - app/Shell/Sidebar.swift
  - app/Views/Jobs/JobsView.swift
  - app/Shell/Router.swift
modified_files:
  - app/Views/Jobs/JobsView.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Deleting the active saved search updates the sidebar selection but does not clear router.activeSavedSearchID or JobsView search tokens/filter state. Clear the active saved-search state and return the jobs view to an explicit All Jobs state.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Deleting the currently selected saved search clears router.activeSavedSearchID.
- [x] #2 The jobs list no longer applies deleted saved-search tokens or text after deletion.
- [x] #3 Tests or UI coverage verify active saved-search deletion returns to All Jobs.
<!-- AC:END -->
