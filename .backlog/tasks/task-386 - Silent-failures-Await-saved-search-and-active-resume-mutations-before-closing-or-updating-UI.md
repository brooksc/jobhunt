---
id: TASK-386
title: >-
  Silent failures: Await saved-search and active-resume mutations before closing
  or updating UI
status: To Do
assignee: []
created_date: '2026-06-12 22:57'
labels:
  - audit
  - error-handling
  - ux
  - settings
dependencies: []
references:
  - app/Views/Jobs/SaveSearchSheet.swift
  - app/Shell/Sidebar.swift
  - app/Views/Settings/ResumesTab.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Save/delete saved search and active resume selection currently use `try?` from UI tasks. The sheet/sidebar/toggle can close or appear updated even when persistence fails. Await these operations, show errors, and keep or restore UI state on failure.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Saving a search does not dismiss the sheet until persistence succeeds.
- [ ] #2 Deleting a saved search reports failure and does not leave navigation in a misleading state.
- [ ] #3 Changing the active resume reports failure and restores the displayed selection if needed.
- [ ] #4 The affected UI commands do not swallow thrown persistence errors.
<!-- AC:END -->
