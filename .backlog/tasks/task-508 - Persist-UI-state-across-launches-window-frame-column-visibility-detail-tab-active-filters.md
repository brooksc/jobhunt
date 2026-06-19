---
id: TASK-508
title: >-
  Persist UI state across launches: window frame, column visibility, detail tab,
  active filters
status: To Do
assignee: []
created_date: '2026-06-19 01:12'
labels:
  - hig
  - state-restoration
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
macOS HIG (1.7/11.3): persist and restore interface state. Today only the sidebar selection persists (custom SettingsStore key) and sort order (jobsSortKey, recently added). Not restored: NavigationSplitView column visibility (sidebar/detail collapse), the detail segmented tab (always resets to Overview), active Jobs filters/search, and window size/position.

Work (prefer the lightest mechanism per item):
- Detail tab: persist last-selected DetailTab (per-app, or reset is acceptable — decide; cheapest is @SceneStorage).
- Column visibility: persist NavigationSplitViewVisibility.
- Window frame: confirm SwiftUI window restoration is enabled (often automatic with macOS "Close windows when quitting an app" off) before adding custom code — may be a no-op.
- Active filters/search: decide whether these *should* persist (they may intentionally reset). If yes, persist filterState.

Note the system's "Restore windows" setting interaction; don't fight the OS. Don't over-engineer — a few @SceneStorage/@AppStorage bindings, not a custom restoration framework.

Evidence: grep found 0 @SceneStorage/@AppStorage; JobDetailView.swift:20 (selectedTab ephemeral); ContentView.swift:9 (columnVisibility ephemeral); Sidebar.swift:351 (only sidebar selection persisted).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Relaunching restores sidebar/detail column visibility
- [ ] #2 Detail tab behavior on relaunch is deliberate (persisted or intentionally reset, documented in the task)
- [ ] #3 Window size/position restoration verified (either works via OS or is wired up)
- [ ] #4 Decision recorded on whether active filters/search persist; implemented accordingly
<!-- AC:END -->
