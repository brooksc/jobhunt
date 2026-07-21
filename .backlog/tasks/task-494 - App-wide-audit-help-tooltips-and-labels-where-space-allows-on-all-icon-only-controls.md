---
id: TASK-494
title: >-
  App-wide audit: help tooltips (and labels where space allows) on all icon-only
  controls
status: To Do
assignee: []
created_date: '2026-06-18 19:29'
updated_date: '2026-07-21 22:59'
labels:
  - ux
  - accessibility
  - audit
dependencies: []
priority: medium
ordinal: 4000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Icon-only controls (toolbar buttons, etc.) across the app lack hover help tags, making them hard to interpret (raised re: the LLM Queue top-right toolbar). A SwiftUI Label's text is an accessibility label, NOT a macOS hover tooltip — `.help(...)` is required for the tooltip.

Per Apple HIG (macOS): provide a help tag for every toolbar item / icon control; labels are encouraged and toolbars support icon+text display where space allows.

Scope: sweep every view's toolbar and icon-only buttons; add `.help(...)` to each; for toolbars with room, consider showing labels (icon+text) for the most ambiguous actions. Start with the main views: Jobs list toolbar (+ / bookmark / sort / filter / ellipsis), Job detail (Source / Re-run / Note / nav chevrons), Sites, Duplicates, Data Quality, Settings, and the window-level group menu (the 88-grid icon).

LLM Queue is already done (TASK-494 baseline).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every icon-only control in the main views has a .help() tooltip describing its action
- [ ] #2 Ambiguous toolbar actions show a text label where space allows (icon+text)
- [ ] #3 Tooltip text is verified to appear on hover (manual or VM screenshot check)
<!-- AC:END -->
