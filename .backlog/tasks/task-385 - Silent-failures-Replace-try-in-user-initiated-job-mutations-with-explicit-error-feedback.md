---
id: TASK-385
title: >-
  Silent failures: Replace try? in user-initiated job mutations with explicit
  error feedback
status: To Do
assignee: []
created_date: '2026-06-12 22:57'
labels:
  - audit
  - error-handling
  - ux
  - jobs
dependencies: []
references:
  - app/Views/Jobs/JobsView.swift
  - app/ContentView.swift
  - app/Views/Detail/JobDetailView.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Audit found many user-facing job commands that mutate data with `try?`, causing failures to look successful. Examples include re-running AI, status changes, archive/delete, mark applied, rating changes, fit-score enqueue, and duplicate unmarking. Deleting also clears selection before persistence succeeds. Replace these command paths with awaited error handling, user-visible feedback, and consistent state recovery.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Job mutation commands no longer use `try?` for persistence or queue operations.
- [ ] #2 Failures show a user-visible error without implying the action succeeded.
- [ ] #3 Delete/archive/status/rating/re-run/apply flows preserve or restore UI state when persistence fails.
- [ ] #4 Bulk actions report partial failure summaries where applicable.
<!-- AC:END -->
