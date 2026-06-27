---
id: TASK-577
title: >-
  Follow-ups: resolve or explicitly carry pending actions when jobs enter
  terminal statuses
status: Done
assignee: []
created_date: '2026-06-20 22:54'
updated_date: '2026-06-27 19:12'
labels:
  - audit
  - needs-action
  - follow-ups
  - job-status
dependencies: []
modified_files:
  - core/Models/Enums.swift
  - core/Models/FollowUpVisibility.swift
  - tests/CoreTests/FollowUpVisibilityTests.swift
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
- [x] #1 Moving a job to terminal status has explicit, tested behavior for existing incomplete follow-ups.
- [x] #2 Needs Action no longer shows ordinary pending follow-ups for archived/closed/expired jobs unless that is a deliberate labeled category.
- [x] #3 Undoing an archive/status change restores follow-up state if the terminal-status transition auto-resolved actions.
- [x] #4 Export pending-action fields use the same terminal-status rule as the UI.
- [x] #5 Tests cover archive, closed/unavailable, and at least one non-terminal status transition with pending actions.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Encoded the invariant "terminal-status jobs have no actionable follow-ups" as a non-mutating filter rather than auto-resolving JobAction rows.

- Added `JobStatus.isTerminal` (passed/archived/closed/duplicate/expired). `rejected` intentionally stays active so a feedback follow-up is still allowed; this is the "labeled/filtered as terminal" option (b) from the task, chosen over auto-completing actions.
- Extended the shared `FollowUpVisibility.isActionable` (TASK-576) to exclude follow-ups whose job is terminal. Since Needs Action + sidebar badge, Dashboard, job detail, and ExportService all already route through that one predicate, every surface suppresses terminal-job follow-ups with no per-surface change (AC#2, AC#4).
- Because nothing is mutated, un-archiving (terminal → active) restores the follow-up automatically — undo is free (AC#3).
- Tests in FollowUpVisibilityTests cover all terminal statuses hiding follow-ups, all non-terminal statuses keeping them, a terminal→active transition restoring, and rejected staying actionable (AC#1, AC#5).
<!-- SECTION:FINAL_SUMMARY:END -->
