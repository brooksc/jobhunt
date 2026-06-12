---
id: TASK-384
title: >-
  Duplicates view: Prevent stale detached scan results from overwriting newer
  state
status: To Do
assignee: []
created_date: '2026-06-12 22:55'
labels:
  - audit
  - concurrency
  - duplicates
  - swiftui
dependencies: []
references:
  - app/Views/Duplicates/DuplicatesView.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
DuplicatesView uses .task(id:) to restart scans, but the expensive scan runs in Task.detached and can publish results after a newer scan has started or after cancellation.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Duplicate scanning uses structured concurrency or checks a generation/cancellation token before publishing results.
- [ ] #2 Older scans cannot overwrite newer pair/jobIndex state.
- [ ] #3 Tests or a focused manual stress check cover rapid job/status changes while the duplicates view is open.
<!-- AC:END -->
