---
id: TASK-177
title: 'Settings: Apply follow-up default days to action and snooze workflows'
status: To Do
assignee: []
created_date: '2026-06-11 22:13'
labels:
  - audit
  - settings
  - workflow
  - actions
dependencies: []
references:
  - app/Views/Settings/SettingsTab.swift
  - app/Views/Detail/JobDetailView.swift
  - app/Views/Needs/NeedsActionView.swift
  - core/Settings/SettingsStore.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The app exposes `followupDefaultDays`, but next-action and snooze workflows hardcode 7 days. Use the configured default when creating next actions and when snoozing actions, or remove/rename the setting if the hardcoded behavior is intentional.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 New next-action due dates default to the configured follow-up interval.
- [ ] #2 Snooze actions use the configured follow-up interval or a clearly separate snooze setting.
- [ ] #3 Tests or UI-state coverage verify non-default follow-up interval behavior.
<!-- AC:END -->
