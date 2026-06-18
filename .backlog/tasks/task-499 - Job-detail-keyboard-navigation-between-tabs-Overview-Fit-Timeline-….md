---
id: TASK-499
title: 'Job detail: keyboard navigation between tabs (Overview/Fit/Timeline/…)'
status: To Do
assignee: []
created_date: '2026-06-18 22:32'
labels:
  - ux
  - keyboard
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The job detail has tabs (Overview, Fit, Timeline, Description, Raw, Compare) but no keyboard way to switch between them while reviewing. Power users reviewing many jobs would benefit from ⌘-arrow (or ⌘1..6) to move between tabs without the mouse.

Scope: add keyboard shortcuts to cycle/select the detail tabs (e.g. ⌃⇥ / ⌘⌥←→ or ⌘1–6), without conflicting with existing global shortcuts. The tab order is already Overview → Fit → Timeline → Description → Raw → Compare.

References: app/Views/Detail/JobDetailView.swift (DetailTab enum + selectedTab).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Keyboard shortcut(s) switch between job-detail tabs without using the mouse
- [ ] #2 Shortcuts don't conflict with existing global commands
<!-- AC:END -->
