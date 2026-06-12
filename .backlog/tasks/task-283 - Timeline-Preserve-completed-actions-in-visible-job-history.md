---
id: TASK-283
title: 'Timeline: Preserve completed actions in visible job history'
status: To Do
assignee: []
created_date: '2026-06-12 03:36'
labels:
  - audit
  - timeline
  - follow-up
  - ux
dependencies: []
references:
  - core/Services/JobService.swift
  - core/Models/JobAction.swift
  - app/Views/Detail/JobDetailView.swift
  - app/Views/Needs/NeedsActionView.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Completing a JobAction sets completedAt, but completed actions disappear from the job timeline because it only renders pending actions and JobEvent rows. Add completed action history or create completion events so follow-through remains visible.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Completed actions are visible in the job timeline/history or produce completion JobEvent records.
- [ ] #2 Needs Action still hides completed actions from active follow-up lists.
- [ ] #3 Tests cover action completion preserving an auditable history entry.
<!-- AC:END -->
