---
id: TASK-330
title: 'Settings restore: Require relaunch or disable writes after restore'
status: Done
assignee: []
created_date: '2026-06-12 20:06'
updated_date: '2026-06-12 20:58'
labels:
  - audit
  - backup
  - restore
  - settings
  - swiftdata
dependencies: []
references:
  - app/Views/Settings/SettingsTab.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
After replacing the on-disk store, SettingsTab lets the user choose Later instead of relaunching immediately. The running SwiftData container may still hold open connections to the previous store, and later writes can conflict with or overwrite restored state.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A successful restore forces immediate app termination/relaunch or places the app into a read-only/blocked state until relaunch.
- [ ] #2 The UI no longer permits normal data mutations against the old open container after restore.
- [ ] #3 Manual or automated validation confirms restored data is what the app opens after relaunch.
<!-- AC:END -->
