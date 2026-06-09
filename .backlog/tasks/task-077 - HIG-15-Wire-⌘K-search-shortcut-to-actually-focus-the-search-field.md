---
id: TASK-077
title: 'HIG-15: Wire ⌘K search shortcut to actually focus the search field'
status: Done
assignee: []
created_date: '2026-06-09 03:00'
updated_date: '2026-06-09 03:18'
labels:
  - hig
  - minor
  - keyboard
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
KeyboardShortcutsTable.swift documents ⌘K as "Open search / jump to Jobs" but it is not wired in commands or as a keyboardShortcut modifier. Wire it properly.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ⌘K focuses the search field in JobsView
- [ ] #2 Works from anywhere in the jobs view
<!-- AC:END -->
