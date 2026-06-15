---
id: TASK-386
title: >-
  Silent failures: Await saved-search and active-resume mutations before closing
  or updating UI
status: Done
assignee: []
created_date: '2026-06-12 22:57'
updated_date: '2026-06-15 05:26'
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
modified_files:
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
- [x] #1 Saving a search does not dismiss the sheet until persistence succeeds.
- [x] #2 Deleting a saved search reports failure and does not leave navigation in a misleading state.
- [x] #3 Changing the active resume reports failure and restores the displayed selection if needed.
- [x] #4 The affected UI commands do not swallow thrown persistence errors.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
SaveSearchSheet.save() now awaits insertSavedSearch and dismisses only on success; on failure it shows an inline error and keeps the sheet (and unsaved form) open (AC#1). Sidebar saved-search delete attempts the delete first and only moves navigation to All Jobs on success; failure shows a toast and leaves navigation intact (AC#2). ResumesTab active-resume toggle surfaces failures via toast — the checkmark is store-backed (resume.active) so a failed write leaves the displayed state correct, no manual restore needed (AC#3). None of the three swallow the thrown error anymore (AC#4). Verified by build; no unit tests (SwiftUI command wiring needs XCUITest).
<!-- SECTION:FINAL_SUMMARY:END -->
