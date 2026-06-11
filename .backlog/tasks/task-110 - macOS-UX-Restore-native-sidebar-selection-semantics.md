---
id: TASK-110
title: 'macOS UX: Restore native sidebar selection semantics'
status: To Do
assignee: []
created_date: '2026-06-11 02:24'
labels:
  - ux
  - macos
  - sidebar
  - accessibility
dependencies: []
references:
  - app/Shell/Sidebar.swift
  - app/Shell/Router.swift
  - tests/AppUITests/AppUITests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`app/Shell/Sidebar.swift` uses `Button` controls inside `List(selection:)` for navigation rows. This looks like a sidebar, but selection is driven by button actions and manual router synchronization rather than a single native selection/navigation mechanism. Refactor the sidebar so keyboard navigation, selection state, and VoiceOver behavior match standard macOS sidebars.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Sidebar navigation uses a single native selection/navigation mechanism rather than plain buttons nested inside a selectable list
- [ ] #2 Keyboard arrow navigation moves through sidebar rows and updates visible selection predictably
- [ ] #3 VoiceOver announces sidebar rows as selectable navigation items with correct selected state
- [ ] #4 Existing sidebar badges, saved-search context menu actions, tooltips, and accessibility identifiers continue to work
- [ ] #5 UI tests cover sidebar keyboard or selection behavior for at least two representative rows
<!-- AC:END -->
