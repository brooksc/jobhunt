---
id: TASK-579
title: 'Follow-ups: surface failed Undo operations instead of swallowing errors'
status: To Do
assignee: []
created_date: '2026-06-20 22:55'
updated_date: '2026-07-21 22:59'
labels:
  - audit
  - follow-ups
  - undo
  - error-handling
dependencies: []
modified_files:
  - app/Views/Needs/NeedsActionView.swift
  - app/Views/Detail/JobDetailView.swift
  - app/Views/Jobs/JobsView.swift
  - core/Services/JobService.swift
  - tests/CoreTests/JobServiceMutationTests.swift
priority: low
ordinal: 32000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: Follow-up completion undo uses `Task { try? await jobService?.reopenAction(actionID:) }` in both `NeedsActionView` and the shared detail helper. Status/archive undo paths in the Jobs list similarly call `try? await svc.setStatus(...)`. If the action/job was deleted, the store fails, or the undo only partially succeeds, the user sees no error and the UI remains changed.

Why it matters: Undo is presented as a reliable recovery command after destructive or state-changing actions. Silently swallowing undo failures creates false confidence and makes data loss or partial restoration hard to diagnose. This repeats a pattern previously addressed for direct user mutations, but the deferred toast action path still has the same risk.

Suggested implementation: Add a small reusable async undo helper that executes the restoration, catches errors, and shows a toast such as `Couldn't undo: ...`. For multi-item status/archive undo, count failures and report partial restoration. Use it for follow-up reopen, archive/status undo, and any similar toast `actionLabel: "Undo"` closures.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Follow-up completion Undo reports an error if reopening the action fails.
- [ ] #2 Archive/status Undo reports partial or total failure instead of using `try?`.
- [ ] #3 No user-facing undo closure swallows errors for JobService mutations in Jobs/Needs/Detail views.
- [ ] #4 Tests or focused UI coverage exercise a failed undo path with a missing action/job.
<!-- AC:END -->
