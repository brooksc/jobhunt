---
id: TASK-519
title: 'State machine: clear stale fit scores when a rescore is queued or pending'
status: To Do
assignee: []
created_date: '2026-06-19 02:00'
labels:
  - audit
  - state-machine
  - fit-score
  - data-integrity
dependencies: []
references:
  - core/Services/BackgroundStore.swift
  - core/Models/Enums.swift
  - tests/CoreTests/JobServiceTests.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: fit-score running state clears stale scores before recomputing the job-level fit mirror, but pending paths such as `markFitScorePending`, `insertFitBatch`, and `enqueueFitForActiveResumes` can mark a record pending while leaving its old `fitScore` in place. The mirror computation selects best scores by non-nil score, so a pending rescore can still make the job look successfully scored with an old value until processing reaches running.

Why this matters: the job-level fit mirror drives user-facing ranking and readiness signals. Showing an old score as current during pending rescoring hides that analysis is stale and can produce inconsistent list ordering or decisions.

Suggested implementation: whenever an existing fit record is moved back to pending for a new run, clear stale score output and recompute the job-level fit mirror immediately. Apply this consistently across manual pending, batch insert/update, and active-resume enqueue paths.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Moving an existing fit record to pending clears stale score output before the job mirror is recomputed.
- [ ] #2 `markFitScorePending`, `insertFitBatch`, and active-resume enqueue paths apply the same pending-state semantics.
- [ ] #3 A job with only pending fit records does not expose an old successful `job.fitScore` or `job.fitStatus == .succeeded`.
- [ ] #4 Successful fit processing still restores the mirror with the new score.
- [ ] #5 Focused tests cover stale-score pending transitions for single and batch enqueue paths.
<!-- AC:END -->
