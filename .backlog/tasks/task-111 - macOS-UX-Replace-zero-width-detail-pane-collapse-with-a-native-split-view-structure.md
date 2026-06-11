---
id: TASK-111
title: >-
  macOS UX: Replace zero-width detail pane collapse with a native split-view
  structure
status: To Do
assignee: []
created_date: '2026-06-11 02:24'
labels:
  - ux
  - macos
  - navigation
  - swiftui
dependencies: []
references:
  - app/ContentView.swift
  - app/Views/Jobs/JobsView.swift
  - app/Views/Sites/SitesView.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`ContentView` uses a three-column `NavigationSplitView` for all app sections, then returns a zero-width detail column for sections that should be full-width. This can produce fragile layout, resizing, accessibility traversal, and future multi-window behavior. Rework the shell so sections without an inspector do not rely on a fake zero-width detail pane.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Full-width sections such as Dashboard, Data Quality, Needs Action, LLM Queue, Duplicates, Help, and Settings no longer render a zero-width detail pane
- [ ] #2 Jobs and Sites still present their inspector/detail panes with expected column widths
- [ ] #3 Sidebar visibility and resizing behavior remain stable across section changes
- [ ] #4 Accessibility traversal does not include an empty fake detail column for full-width sections
- [ ] #5 Screenshot or UI coverage verifies at least one inspector section and one full-width section
<!-- AC:END -->
