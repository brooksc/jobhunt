---
id: TASK-108
title: 'macOS UX: Align app commands and documented keyboard shortcuts'
status: Done
assignee: []
created_date: '2026-06-11 02:23'
updated_date: '2026-06-11 02:53'
labels:
  - ux
  - macos
  - commands
  - accessibility
dependencies: []
references:
  - app/Views/Help/KeyboardShortcutsTable.swift
  - app/JobhuntApp.swift
  - app/Views/Jobs/JobsView.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The Help screen documents macOS keyboard workflows that are not currently backed by app-level commands. `app/Views/Help/KeyboardShortcutsTable.swift` lists `⌘K`, arrow navigation, Return-to-open, Escape, `⌘N`, and `⌘⇧E`, but `app/JobhuntApp.swift` only registers `⌘N` and `⌘⇧E`. Close the gap so documented shortcuts either work consistently or are removed from Help.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Every shortcut shown in the Help keyboard shortcuts table is implemented and verified, or the Help table is updated to remove unsupported shortcuts
- [x] #2 `⌘K` focuses job search or performs the documented jump-to-Jobs search behavior from any app section
- [ ] #3 Keyboard shortcut behavior is covered by focused UI tests or equivalent automated verification where feasible
- [x] #4 App menu commands expose primary shortcut-backed actions using native macOS command surfaces
<!-- AC:END -->
