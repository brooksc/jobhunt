---
id: TASK-087
title: 'Fix NeedsActionView: Snooze All Overdue fires without confirmation'
status: To Do
assignee: []
created_date: '2026-06-10 07:31'
labels:
  - bug
  - ui-audit
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
HIGH: `Snooze All Overdue` button calls `snoozeAllOverdue()` directly and irreversibly. `isSnoozeAllConfirming: Bool` state is declared but never used in a `confirmationDialog`. Fix: wire up the existing state to a `.confirmationDialog` before calling the action.

MEDIUM: When a filter is active, only the filtered overdue subset is snoozed. The button label should indicate this (e.g., "Snooze X Overdue" showing the count).

Files: `app/Views/NeedsAction/NeedsActionView.swift`
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Snooze All Overdue shows a confirmation dialog before acting
- [ ] #2 Button label shows count of actions that will be snoozed
- [ ] #3 When filter is active, label/dialog clarifies it acts on filtered subset only
<!-- AC:END -->
