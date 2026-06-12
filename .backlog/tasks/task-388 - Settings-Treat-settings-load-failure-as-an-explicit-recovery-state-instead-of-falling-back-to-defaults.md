---
id: TASK-388
title: >-
  Settings: Treat settings load failure as an explicit recovery state instead of
  falling back to defaults
status: To Do
assignee: []
created_date: '2026-06-12 22:58'
labels:
  - audit
  - error-handling
  - settings
dependencies: []
references:
  - core/Settings/SettingsStore.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
SettingsStore loads cached settings with `(try? fetchSettings()) ?? []`. If persistence fails, the app can silently run with defaults and later writes may overwrite real preferences. Surface the load failure, preserve the last known settings where possible, and avoid writing defaults over unread settings without user awareness.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Settings load errors are captured in an explicit error/recovery state.
- [ ] #2 The UI communicates that settings could not be loaded rather than showing ordinary defaults as authoritative.
- [ ] #3 The app does not persist default settings over unread stored settings during a load failure.
- [ ] #4 Tests cover load failure behavior and recovery after the store becomes readable.
<!-- AC:END -->
