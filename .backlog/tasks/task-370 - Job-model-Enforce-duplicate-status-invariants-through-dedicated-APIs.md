---
id: TASK-370
title: 'Job model: Enforce duplicate status invariants through dedicated APIs'
status: Done
assignee: []
created_date: '2026-06-12 22:26'
updated_date: '2026-06-15 19:45'
labels:
  - audit
  - data-model
  - invariants
  - duplicates
dependencies: []
references:
  - core/Models/Job.swift
  - core/Services/JobService.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Job documents duplicateOfJobID != nil as requiring status == .duplicate, but generic status and field update paths can change duplicateOfJobID or status independently and create inconsistent rows.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Introduce dedicated markDuplicate/clearDuplicate or invariant-repair APIs for duplicate state changes.
- [x] #2 Generic job update/status paths preserve or repair duplicate invariants consistently.
- [x] #3 Tests cover setting status on duplicate jobs, clearing duplicateOfJobID, and marking duplicates through supported APIs.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Enforced the Job duplicate invariant (`duplicateOfJobID != nil` ⇒ `status == .duplicate`) at every supported mutation. Added `JobService.markDuplicate(jobID:ofJobID:confidence:)` which sets the link and `.duplicate` status atomically (symmetric with the existing `unmarkDuplicate`/clearDuplicate). `setStatus` now repairs the invariant — moving a flagged duplicate to any non-`.duplicate` status clears `duplicateOfJobID`/`duplicateConfidence` — while re-setting `.duplicate` preserves an existing link. `updateJobFields` repairs it when `duplicateOfJobID` changes: setting a link forces `.duplicate`; clearing it resets a `.duplicate` job to `.new`. The automatic detector (`BackgroundStore.detectAndFlagDuplicates`) already set both fields together. Tests (CoreTests/JobServiceTests): markDuplicate atomicity, setStatus clear-on-leave + keep-on-reduplicate, updateJobFields set/clear. Full JobServiceTests green; app builds.
<!-- SECTION:FINAL_SUMMARY:END -->
