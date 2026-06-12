---
id: TASK-238
title: 'Diagnostics: Surface settings persistence failures outside NSLog'
status: To Do
assignee: []
created_date: '2026-06-12 01:51'
labels:
  - diagnostics
  - settings
dependencies: []
references:
  - core/Settings/SettingsStore.swift
  - app/Views/Settings/SettingsTab.swift
  - app/Views/Settings/DebugTab.swift
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
SettingsStore logs persistence failures to NSLog only. Add a visible or queryable diagnostics path so settings write failures can be noticed and reported from the app.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Settings persistence failures are surfaced in app diagnostics or a user-visible error state.
- [ ] #2 Sensitive setting values are not logged or displayed.
- [ ] #3 The diagnostics surface includes the setting key and sanitized error context.
- [ ] #4 Tests cover persistence failure handling where practical.
<!-- AC:END -->
