---
id: TASK-066
title: 'HIG-2: Move Settings to a dedicated Settings scene with ⌘,'
status: To Do
assignee: []
created_date: '2026-06-09 02:59'
labels:
  - hig
  - critical
  - settings
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Settings is currently a sidebar nav item that renders SettingsView in the content column. macOS requires a Settings { } scene in JobhuntApp.swift opened via ⌘, from the app menu. Remove .settings from SidebarSection.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Settings scene added to JobhuntApp
- [ ] #2 ⌘, opens Settings in a separate window
- [ ] #3 Settings removed from sidebar navigation
- [ ] #4 App menu shows Settings… item
<!-- AC:END -->
