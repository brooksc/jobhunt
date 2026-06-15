---
id: TASK-388
title: >-
  Settings: Treat settings load failure as an explicit recovery state instead of
  falling back to defaults
status: Done
assignee: []
created_date: '2026-06-12 22:58'
updated_date: '2026-06-15 05:05'
labels:
  - audit
  - error-handling
  - settings
dependencies: []
references:
  - core/Settings/SettingsStore.swift
modified_files:
  - core/Settings/SettingsStore.swift
  - app/Views/Settings/SettingsView.swift
  - tests/CoreTests/SettingsStoreTests.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
SettingsStore loads cached settings with `(try? fetchSettings()) ?? []`. If persistence fails, the app can silently run with defaults and later writes may overwrite real preferences. Surface the load failure, preserve the last known settings where possible, and avoid writing defaults over unread settings without user awareness.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Settings load errors are captured in an explicit error/recovery state.
- [x] #2 The UI communicates that settings could not be loaded rather than showing ordinary defaults as authoritative.
- [x] #3 The app does not persist default settings over unread stored settings during a load failure.
- [ ] #4 Tests cover load failure behavior and recovery after the store becomes readable.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
loadCache now catches a store-read failure and enters a recovery state (public loadError) instead of `(try? fetchSettings()) ?? []` silently running on defaults. While loadError is set, persistToStore skips writes so a default can't overwrite stored settings that merely couldn't be read (AC#3). Added reload() to re-attempt the load and clear the state once the store is readable again. SettingsView shows a recovery banner when loadError is set (AC#2). AC#4 partial: tests cover the readable/recovered baseline (load → persist → reload → reopen); the actual load-FAILURE path can't be unit-tested — SwiftData's fetch doesn't throw on demand (a schema omitting Setting returns empty, not an error) and there's no failure-injection seam on ModelContext/BackgroundStore. Same seam gap as TASK-387/389 — a shared Store protocol seam would unblock all three.
<!-- SECTION:FINAL_SUMMARY:END -->
