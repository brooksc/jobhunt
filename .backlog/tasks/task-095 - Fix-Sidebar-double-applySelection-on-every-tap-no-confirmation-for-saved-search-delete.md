---
id: TASK-095
title: >-
  Fix Sidebar: double applySelection on every tap, no confirmation for saved
  search delete
status: To Do
assignee: []
created_date: '2026-06-10 07:32'
labels:
  - bug
  - ui-audit
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
MEDIUM: Every sidebar button fires `applySelection` twice — once in the button closure and once from `.onChange(of: listSelection)`. Fix: remove the direct call from button closures and rely solely on `.onChange`, or vice versa.

MEDIUM: Saved search `Delete` context menu item calls `modelContext.delete(search)` immediately with no confirmation. Deletion is unrecoverable. Fix: add a `confirmationDialog` before deleting.

LOW: `syncSelectionFromRouter` maps `.help` → `.dashboard`, so Dashboard sidebar row is highlighted when user is in Help section. Fix the mapping.

Files: `app/Views/Sidebar/Sidebar.swift`
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Clicking a sidebar item calls applySelection exactly once
- [ ] #2 Deleting a saved search requires confirmation
- [ ] #3 Help section does not highlight Dashboard in the sidebar
<!-- AC:END -->
