---
id: TASK-071
title: 'HIG-9: Move .sheet for rename to parent view level in Sidebar'
status: To Do
assignee: []
created_date: '2026-06-09 03:00'
labels:
  - hig
  - moderate
  - sidebar
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
savedSearchNavItem() attaches .sheet(item: $renamingSearch) inside the ForEach row. Move the sheet modifier to the scrollableNav or body level of Sidebar to avoid presentation races.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Sheet modifier is on Sidebar body or scrollableNav, not on row buttons
- [ ] #2 Rename functionality still works correctly
<!-- AC:END -->
