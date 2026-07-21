---
id: TASK-509
title: Sidebar selection should track the system accent color (drop hardcoded blue)
status: To Do
assignee: []
created_date: '2026-06-19 01:13'
updated_date: '2026-07-21 22:59'
labels:
  - hig
  - color
dependencies: []
priority: low
ordinal: 24000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
macOS HIG (11.5/19.3): selection and primary accents should track the user's chosen accent color and adapt to appearance/inactive states. The sidebar paints its selected row with a hardcoded `Color(red: 0.0, green: 0.32, blue: 0.75)` and white text (Sidebar.swift:10, :203) instead of using native sidebar selection / `.accentColor`, so it ignores a non-blue accent and likely doesn't dim when the window is inactive.

Investigate why selection is custom-rendered (possibly to support AppKit-identifier-based UI-test selection) and, if compatible, switch to native `List` sidebar selection or `.tint(.accentColor)` so it tracks the accent and inactive state. If the custom rendering must stay for testability, at minimum derive the color from the accent and handle the inactive (key-window) state.

Out of scope / intentionally kept: fit-score green/amber/red rings (semantic quality scale, not selection) — those are addressed for accessibility in the VoiceOver task, not recolored here.

Evidence: Sidebar.swift:10 (sidebarSelectionColor RGB literal), :203 (Color.white text).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Sidebar selection color follows the user's system accent color
- [ ] #2 Selection appearance respects active vs inactive window state
- [ ] #3 UI-test sidebar selection (accessibilityIdentifier-based) still works
- [ ] #4 No regression in light/dark mode contrast
<!-- AC:END -->
