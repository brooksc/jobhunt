---
id: TASK-083
title: >-
  Fix JobsView: multi-select delete, missing confirmation, and searchText not
  synced to filterState
status: Done
assignee: []
created_date: '2026-06-10 07:30'
updated_date: '2026-06-10 22:24'
labels:
  - bug
  - ui-audit
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Three bugs in JobsView:

HIGH: Context menu `Delete Job` ignores multi-select. Uses `job.id` (right-clicked item) while all other menu items use `selectedJobIDs`. Fix: delete all selected IDs when selection is non-empty.

MEDIUM: Delete fires immediately with no confirmation. Should show a `confirmationDialog` before deleting (cascade removes captures, events, contacts, cover letters).

MEDIUM (3 related): `@State var searchText` is never synced to `filterState.searchText`. Results:
- Saved searches never include free-text queries
- Save Search bookmark icon never shows for text-only searches  
- Clear All Filters not shown when only free-text is active
Fix: sync searchText into filterState on change so all downstream logic uses it.

Files: `app/Views/Jobs/JobsView.swift`
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Delete with multi-select deletes all selected jobs
- [ ] #2 Delete shows confirmation dialog listing affected count
- [ ] #3 Typed search text is reflected in filterState.searchText
- [ ] #4 Save Search bookmark icon appears for text-only searches
- [ ] #5 Clear All Filters appears when only free-text search is active
<!-- AC:END -->
