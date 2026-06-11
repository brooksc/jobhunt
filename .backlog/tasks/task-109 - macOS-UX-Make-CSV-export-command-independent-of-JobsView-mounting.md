---
id: TASK-109
title: 'macOS UX: Make CSV export command independent of JobsView mounting'
status: To Do
assignee: []
created_date: '2026-06-11 02:23'
labels:
  - ux
  - macos
  - commands
dependencies: []
references:
  - app/JobhuntApp.swift
  - app/Shell/Router.swift
  - app/Views/Jobs/JobsView.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The app-level `Export Jobs to CSV…` command currently sets `router.triggerExport`, while the only handler lives in `JobsView.onChange`. If the user invokes the command while Dashboard, Queue, Settings, or another section is active, `JobsView` may not be mounted and the command can do nothing. Move export command handling to an app/service command path or otherwise make the menu command reliable from every section where it is enabled.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Invoking `Export Jobs to CSV…` from any app section where the command is enabled opens the save panel and exports the intended job set
- [ ] #2 The command is disabled or clearly unavailable in states where export cannot be performed
- [ ] #3 Export behavior no longer depends on `JobsView` being mounted to observe router state
- [ ] #4 UI or integration coverage verifies export command routing outside the Jobs section
<!-- AC:END -->
