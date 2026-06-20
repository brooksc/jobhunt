---
id: TASK-577
title: >-
  Follow-ups: resolve or explicitly carry pending actions when jobs enter
  terminal statuses
status: To Do
assignee: []
created_date: '2026-06-20 22:54'
labels:
  - audit
  - needs-action
  - follow-ups
  - job-status
dependencies: []
modified_files:
  - core/Services/JobService.swift
  - app/Views/Jobs/JobsView.swift
  - app/Views/Detail/JobDetailView.swift
  - app/Views/Needs/NeedsActionView.swift
  - core/Services/ExportService.swift
  - tests/CoreTests/JobServiceTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: `JobService.archive(jobID:)` and status changes to closed/rejected/expired only update the job status; they do not resolve incomplete `JobAction` rows. `NeedsActionView` then continues to show pending actions for archived or unavailable jobs whenever those actions are unsnoozed, and export reports them as open. Existing availability logic treats passed/archived/closed/expired as terminal elsewhere, but follow-up lifecycle does not participate in that rule.

Why it matters: A user can archive or close a job and still be nagged to follow up on it. That makes the workflow feel inconsistent and creates hidden cleanup work. The domain invariant should be explicit: either terminal jobs cannot have actionable follow-ups, or the app intentionally carries them with clear labeling.

Suggested implementation: Decide and encode the invariant in `JobService.setStatus`. The likely default is to complete/cancel pending actions when moving into terminal statuses (`archived`, `closed`, `expired`, `passed`, possibly `rejected`), with an undo strategy that restores both prior status and prior follow-up state when the user undoes the status change. If product intent is to allow follow-ups for rejected/archived jobs, make Needs Action label/filter those as terminal follow-ups rather than mixing them with active pipeline work.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Moving a job to terminal status has explicit, tested behavior for existing incomplete follow-ups.
- [ ] #2 Needs Action no longer shows ordinary pending follow-ups for archived/closed/expired jobs unless that is a deliberate labeled category.
- [ ] #3 Undoing an archive/status change restores follow-up state if the terminal-status transition auto-resolved actions.
- [ ] #4 Export pending-action fields use the same terminal-status rule as the UI.
- [ ] #5 Tests cover archive, closed/unavailable, and at least one non-terminal status transition with pending actions.
<!-- AC:END -->
