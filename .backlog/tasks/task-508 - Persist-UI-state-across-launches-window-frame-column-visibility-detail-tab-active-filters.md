---
id: TASK-508
title: >-
  Persist UI state across launches: window frame, column visibility, detail tab,
  active filters
status: Done
assignee: []
created_date: '2026-06-19 01:12'
updated_date: '2026-08-10 00:37'
labels:
  - hig
  - state-restoration
dependencies: []
modified_files:
  - app/ContentView.swift
  - app/Platform/WindowPolicy.swift
priority: low
ordinal: 23000
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
- [x] #1 Relaunching restores sidebar/detail column visibility
- [x] #2 Detail tab behavior on relaunch is deliberate (persisted or intentionally reset, documented in the task)
- [x] #3 Window size/position restoration verified (either works via OS or is wired up)
- [x] #4 Decision recorded on whether active filters/search persist; implemented accordingly
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
#1 Column visibility persists via `@SceneStorage`, stored as a token because `NavigationSplitViewVisibility` isn't `RawRepresentable`. `detailOnly` is deliberately **not** restored as itself — relaunching into a hidden sidebar with no selected job leaves an empty window and no obvious way back — so it restores as `all`.

#2 **Already shipped, verified rather than re-done.** `JobDetailView.stickyTabSelection` writes the deliberately-chosen tab to `SettingsStore.detailLastTab` and `restoreStickyTab()` seeds from it, ignoring a saved tab that isn't visible for the current job. Decision recorded: the tab is sticky across jobs *and* relaunch, because a user working through fit scores wants the Fit tab, not Overview, on every job. One-off jumps (the Overview "see Fit" button) assign directly and bypass the stickiness, so they don't become the default.

#3 Wired rather than assumed. SwiftUI restores a window frame only when the system's "Close windows when quitting an app" is off — a setting we don't control and shouldn't fight — so `WindowPolicy` sets an AppKit `frameAutosaveName`, which persists size and position either way. Set once per window: AppKit reads the saved frame on first assignment only.

#4 **Decision: filters and search do not persist.** A filter you've forgotten about is hidden data — the list looks wrong and the reason is off-screen — and the sidebar selection and sort order that *do* persist are enough to land the user back where they were. No code; recorded here so it isn't re-litigated.

Gate: fast gate TEST SUCCEEDED, BUILD SUCCEEDED, swiftlint 0 violations in 344 files, swiftformat clean, warning ratchet 58/58.

not verified: (visual) — that the restored frame and column state actually appear on a second launch. That needs quitting and relaunching the app on a live desktop; the wiring is compile-checked.
<!-- SECTION:FINAL_SUMMARY:END -->
