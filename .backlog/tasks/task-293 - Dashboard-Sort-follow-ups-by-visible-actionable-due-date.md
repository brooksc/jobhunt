---
id: TASK-293
title: 'Dashboard: Sort follow-ups by visible actionable due date'
status: Done
assignee: []
created_date: '2026-06-12 04:39'
updated_date: '2026-06-12 05:47'
labels:
  - audit
  - dashboard
  - follow-up
  - ux
dependencies: []
references:
  - app/Views/Dashboard/DashboardView.swift
  - app/Views/Needs/NeedsActionView.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Dashboard Follow-ups Due filters out snoozed future actions, but sorting considers all incomplete actions and can order a job by a hidden snoozed action. Sort using the same visible/actionable action set used for filtering.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Follow-ups Due sorting ignores snoozed future actions.
- [ ] #2 The displayed due badge corresponds to the action used for sorting.
- [ ] #3 Tests cover a job with one snoozed action and one visible due action.
<!-- AC:END -->
