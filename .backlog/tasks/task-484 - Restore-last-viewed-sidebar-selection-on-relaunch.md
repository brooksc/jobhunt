---
id: TASK-484
title: Restore last-viewed sidebar selection on relaunch
status: Done
assignee: []
created_date: '2026-06-18 03:45'
updated_date: '2026-06-18 03:45'
labels:
  - ux
  - navigation
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
When the user quits and reopens the app, it should open on the same view they were on (e.g. the "Pursuing" smart folder), instead of always defaulting to All Jobs.

Implemented: persist the current sidebar selection (section + job-status filter + active saved search) as an opaque token in SettingsStore, and restore it on the sidebar's first appear. Falls back to the default view if nothing is stored or a saved search has since been deleted.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Relaunching opens on the last-viewed sidebar selection (section + job-status smart folder, e.g. Pursuing)
- [x] #2 A saved-search selection that no longer exists falls back to the default view (no broken/empty selection)
- [x] #3 First-ever launch (nothing persisted) shows the default view
<!-- AC:END -->



## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The app now restores the last-viewed sidebar selection on relaunch.

- `SettingsKey.lastSidebarSelection` + `SettingsStore.lastSidebarSelection` (String, default "") persist the view as an opaque token, backed by the SwiftData settings store.
- `SidebarItem.persistedID` / `init?(persistedID:)` (Router.swift) serialize the full selection — section, `jobs:<status>` smart folder, and `savedSearch:<id>` — round-trip.
- `Sidebar` persists the current selection in `syncSelectionFromRouter` (gated by a `didRestore` flag so the pre-restore default can't clobber the saved value) and restores it once on first `onAppear` via `restoreSelection()`, which falls back to the default view when nothing is stored or a saved search has been deleted (AC#2/#3).

Tests: two CoreTests (`SettingsStoreTests`) cover the new persisted property (default empty + round-trip). The `SidebarItem` serialization is build-verified (it lives in the app target, which has no unit-test bundle), and an end-to-end relaunch UITest isn't feasible because `--ui-test-store` is wiped fresh on every launch by design (TASK-424). App builds; full fast gate green.

Scope note: every section is restored, including Settings/Help/LLM Queue — literally "the same view." If reopening onto Settings after a notification deep-link proves undesirable, restoration can be scoped to content sections later.
<!-- SECTION:FINAL_SUMMARY:END -->
