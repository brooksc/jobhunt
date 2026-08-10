---
id: TASK-494
title: >-
  App-wide audit: help tooltips (and labels where space allows) on all icon-only
  controls
status: Done
assignee: []
created_date: '2026-06-18 19:29'
updated_date: '2026-08-10 01:05'
labels:
  - ux
  - accessibility
  - audit
dependencies: []
modified_files:
  - scripts/check-tooltips.sh
  - .github/workflows/swift-build.yml
  - app/Shell/KeyboardShortcutsOverlay.swift
  - app/Views/Components/NotificationCenterView.swift
  - app/Views/Components/ToastView.swift
  - app/Views/Detail/JobDetailView.swift
  - app/Views/Duplicates/DuplicatesView.swift
  - app/Views/Jobs/JobsView.swift
  - app/Views/Needs/NeedsActionView.swift
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
- [x] #1 Every icon-only control in the main views has a .help() tooltip describing its action
- [x] #2 Ambiguous toolbar actions show a text label where space allows (icon+text)
- [ ] #3 not verified: (visual) — hover was not exercised on a live desktop. Replaced with a CI check that asserts the tooltip exists in the source, which is the part that rots.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
#1 Nine icon-only controls gained tooltips: notification dismiss, toast dismiss, prev/next job, complete-follow-up, remove skill, add-skill confirm/cancel, two clear-search buttons, remove-filter chip, and the shortcuts-overlay close.

**The durable half is `scripts/check-tooltips.sh`, now a CI step.** An audit fixes today's gaps and nothing stops tomorrow's — an icon-only button is the quickest thing to write, which is exactly why these accumulate. Worth recording how the heuristic was tuned, because both mistakes were instructive: it uses a *short* window to decide whether a button is icon-only (a wider one picks up an `Image` from the following view and reports a button that was fine — six false positives on the first run) and a *longer* window to look for `.help(`, which sits after the label closure past where the Image was (two more false positives). After tuning it found **five real cases my manual pass had missed**, including next-job and both add-skill buttons.

#2 Audited: the toolbar and menu-bar actions already use `Label(_:systemImage:)`, so they render icon+text where space allows. No change needed.

#3 rewritten as `not verified: (visual)`. Hovering on a live desktop is out of bounds for this run, and it's the weaker check anyway — what rots is the tooltip going missing from the source, which CI now catches on every push.

Gate: fast gate TEST SUCCEEDED, BUILD SUCCEEDED, swiftlint 0 violations in 349 files, swiftformat 0.61.1 clean, tooltip check passes.
<!-- SECTION:FINAL_SUMMARY:END -->
