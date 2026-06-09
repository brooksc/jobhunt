---
id: TASK-067
title: 'HIG-4: Remove or make interactive the non-actionable status icons in toolbar'
status: To Do
assignee: []
created_date: '2026-06-09 02:59'
labels:
  - hig
  - critical
  - toolbar
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ContentView.swift places three non-tappable Image views (bolt, puzzlepiece, cpu) in the toolbar with only .help() tooltips. Toolbar items must be interactive or moved elsewhere. Convert to a single tappable status Menu or remove them.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 No non-interactive images in toolbar
- [ ] #2 Status info accessible via a tappable Menu or moved to sidebar/status bar
<!-- AC:END -->
