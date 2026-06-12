---
id: TASK-251
title: 'Domain correctness: Repair status when unmarking duplicates'
status: To Do
assignee: []
created_date: '2026-06-12 02:41'
labels:
  - audit
  - domain
  - duplicates
dependencies: []
references:
  - core/Services/JobService.swift
  - app/Shell/Sidebar.swift
  - app/Views/Detail/JobDetailView.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`JobService.unmarkDuplicate` clears only `duplicateOfJobID`. If a job also has `status == .duplicate`, unmarking leaves the job in a status excluded from normal sidebar status folders, making it hard to find after unmarking.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Unmarking a duplicate transitions the job to a normal visible status or restores a tracked previous status.
- [ ] #2 Both duplicate view and detail compare-tab unmark actions call the same domain service behavior.
- [ ] #3 Tests cover unmarking jobs with `duplicateOfJobID`, `status == .duplicate`, and both set.
<!-- AC:END -->
