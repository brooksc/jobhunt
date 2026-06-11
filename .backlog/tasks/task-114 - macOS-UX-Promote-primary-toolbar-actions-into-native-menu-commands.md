---
id: TASK-114
title: 'macOS UX: Promote primary toolbar actions into native menu commands'
status: To Do
assignee: []
created_date: '2026-06-11 02:24'
labels:
  - ux
  - macos
  - commands
  - toolbar
dependencies: []
references:
  - app/JobhuntApp.swift
  - app/Views/Jobs/JobsView.swift
  - app/Views/Queue/LLMQueueView.swift
  - app/Views/Quality/DataQualityView.swift
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Several primary workflows are available only through toolbars or context menus: re-run AI, archive selected jobs, process/cancel/reset queue items, mark reviewed, and queue re-extraction. On macOS, important commands should generally be available through the menu bar with clear enablement and shortcuts where appropriate. Build a coherent command model for these workflows rather than leaving them as view-local toolbar-only actions.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Primary Jobs actions exposed in the toolbar or context menu are also represented in native app menus where appropriate
- [ ] #2 Primary LLM Queue actions exposed in the toolbar or context menu are also represented in native app menus where appropriate
- [ ] #3 Primary Data Quality actions exposed in the toolbar are also represented in native app menus where appropriate
- [ ] #4 Menu items have correct enablement based on selection and current section
- [ ] #5 At least one UI test or integration check verifies a non-export menu command reaches the intended action path
<!-- AC:END -->
