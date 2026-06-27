---
id: TASK-578
title: >-
  JobService: throw missing-job errors when creating linked notes and follow-ups
  no-ops
status: Done
assignee: []
created_date: '2026-06-20 22:55'
updated_date: '2026-06-27 19:05'
labels:
  - audit
  - job-service
  - follow-ups
  - data-integrity
dependencies: []
modified_files:
  - core/Services/BackgroundStore.swift
  - core/Services/JobService.swift
  - app/Views/Detail/JobDetailView.swift
  - app/Views/Needs/NeedsActionView.swift
  - tests/CoreTests/JobServiceMutationTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: `BackgroundStore.insertJobEvent` and `insertJobAction` fetch the parent job and `return` if it is missing. `JobService.addNote` and `createAction` therefore complete successfully even when the target job has been deleted, and callers such as `SetNextActionSheet` dismiss as if the follow-up was saved. The service already has `JobServiceError.jobNotFound`, but linked-child insert paths bypass it.

Why it matters: User-initiated writes can look successful while persisting nothing. This is especially likely around async UI flows where a job can be deleted or navigation can change while a sheet/popover is open. It also makes tests and diagnostics weaker because no error tells the caller that the parent job disappeared.

Suggested implementation: Change linked-child creation helpers to return a success/failure signal or throw `BackgroundStoreError.notFound`, then map that to `JobServiceError.jobNotFound` in `JobService.createAction`, `addNote`, `restoreNote`, and other user-facing linked insert APIs. Keep any genuinely best-effort system event writes explicitly named as best effort, not reused by user-facing commands.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Creating a follow-up for a missing job throws a user-visible missing-job error and does not dismiss as saved.
- [x] #2 Adding/restoring a user note for a missing job throws a user-visible missing-job error.
- [x] #3 Best-effort system event writes, if still needed, are separated from user-facing note/action APIs by name or wrapper.
- [x] #4 Tests cover missing-job createAction and addNote/restoreNote behavior.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
BackgroundStore.insertJobAction now throws BackgroundStoreError.notFound when the parent job is gone (was a silent no-op); insertJobEvent gained a requireJob flag — default false keeps system events (e.g. QueueActor's extraction timeline entry) best-effort, true for user-facing notes. JobService.addNote, restoreNote, and createAction pass requireJob:true / use the throwing action insert and map notFound → JobServiceError.jobNotFound, so a sheet/popover can't dismiss as saved after the job was deleted mid-flow (AC#1/#2). Best-effort system writes stay best-effort via the default (AC#3). Tests: testCreateAction_missingJob_throwsJobNotFound / testAddNote_missingJob_throwsJobNotFound / testRestoreNote_missingJob_throwsJobNotFound, asserting the error and that nothing is persisted (AC#4). Full CoreTests (954) green; lint clean.
<!-- SECTION:FINAL_SUMMARY:END -->
