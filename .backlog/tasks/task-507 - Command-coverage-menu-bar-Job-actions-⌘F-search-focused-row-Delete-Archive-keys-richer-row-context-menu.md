---
id: TASK-507
title: >-
  Command coverage: menu-bar Job actions, ⌘F search, focused-row Delete/Archive
  keys, richer row context menu
status: In Progress
assignee: []
created_date: '2026-06-19 01:12'
updated_date: '2026-06-19 01:19'
labels:
  - hig
  - keyboard
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
macOS HIG (3.6/3.8/5.7/9.2/10.3): core actions should be reachable from the menu bar and keyboard, not only toolbar/context menus.

Gaps found:
- No domain Job actions in the menu bar (Archive, Mark Applied/Interested, Re-run Extraction, Open Posting). Add a small `CommandMenu("Job")` (or place under an existing menu) driven by the current selection via FocusedValue, mirroring the row context menu.
- Search is bound to ⌘K only; macOS convention for find/search is ⌘F. Add ⌘F as an alias that focuses the Jobs search field (keep ⌘K).
- No keyboard Delete/Archive on the focused job row (⌫ / ⌘⌫). Add `.onKeyPress`/keyboard shortcut wired to the same archive/delete paths (with the same confirmation/undo).
- Row context menu is missing: Open Posting, Copy Job Link, Add Note. Add them (Open Posting + Copy Link operate on job.sourceURL/applicationURL).

Use Title-Style Capitalization and ellipses only where a sheet/picker follows (already compliant elsewhere).

Evidence: JobhuntApp.swift:251 (⌘K search), JobsView.swift:694 (context menu lacks Open/Copy/Note), no .onKeyPress in JobsView, AppCommands.swift (existing FocusedValue menu pattern to copy).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A menu-bar Job menu exposes Open Posting, Mark Applied, Mark Interested, Re-run Extraction, Archive, Delete acting on the current selection
- [ ] #2 ⌘F focuses the Jobs search field (⌘K still works)
- [ ] #3 Delete/Archive can be triggered from the keyboard on the focused/selected row(s), honoring existing confirm/undo
- [ ] #4 Row context menu includes Open Posting, Copy Job Link, and Add Note
<!-- AC:END -->
