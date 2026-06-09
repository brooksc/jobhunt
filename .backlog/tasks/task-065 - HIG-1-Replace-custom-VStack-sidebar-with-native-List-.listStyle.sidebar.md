---
id: TASK-065
title: 'HIG-1: Replace custom VStack sidebar with native List + .listStyle(.sidebar)'
status: Done
assignee: []
created_date: '2026-06-09 02:59'
updated_date: '2026-06-09 03:18'
labels:
  - hig
  - critical
  - sidebar
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Sidebar.swift builds nav from manually-styled Buttons in a VStack. macOS requires List(selection:).listStyle(.sidebar) with NavigationLink items for correct vibrancy, full-bleed selection pill, keyboard focus ring, and Liquid Glass rendering on Sequoia.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Sidebar uses List with .listStyle(.sidebar)
- [ ] #2 Section headers use Section {}
- [ ] #3 Selection highlight matches system source-list style
- [ ] #4 Keyboard arrow navigation works in sidebar
<!-- AC:END -->
