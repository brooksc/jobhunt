---
id: TASK-115
title: 'macOS UX: Expand UI tests beyond screenshot smoke coverage'
status: To Do
assignee: []
created_date: '2026-06-11 02:24'
labels:
  - ux
  - macos
  - tests
  - accessibility
dependencies: []
references:
  - tests/AppUITests/AppUITests.swift
  - tests/AppUITests/ScreenshotTests.swift
  - tests/AppUITests/JobsScreenUITests.swift
  - app/Views/Help/KeyboardShortcutsTable.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The current AppUITests provide a screenshot tour and limited sidebar navigation coverage. They do not appear to assert macOS-specific behavior such as command routing, keyboard shortcuts, sidebar keyboard selection, filter accessibility state, or toolbar/menu enablement. Add behavior-focused UI tests so screenshot coverage is complemented by regression checks for core desktop interactions.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 UI tests verify at least one app-level menu command from a non-default section
- [ ] #2 UI tests verify documented keyboard shortcuts that remain in Help, including search focus if `⌘K` remains documented
- [ ] #3 UI tests verify sidebar selection or keyboard navigation behavior
- [ ] #4 UI tests verify at least one accessible selected-state filter control
- [ ] #5 Screenshot tests remain available for visual smoke coverage but are not the only coverage for desktop UX behavior
<!-- AC:END -->
