---
id: TASK-518
title: 'State machine: clear duplicate confidence whenever duplicate link is cleared'
status: Done
assignee: []
created_date: '2026-06-19 02:00'
updated_date: '2026-06-19 05:07'
labels:
  - audit
  - state-machine
  - duplicates
  - data-integrity
dependencies: []
references:
  - core/Services/JobService.swift
  - core/Services/BackgroundStore.swift
  - tests/CoreTests/JobServiceTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: duplicate state has a partial invariant: `setStatus` and some field-update paths clear duplicate metadata when a job is no longer duplicate, but `unmarkDuplicate` and same-URL recapture can clear `duplicateOfJobID` while leaving `duplicateConfidence` behind.

Why this matters: `duplicateConfidence` only has meaning when `duplicateOfJobID` points at a canonical job. Leaving confidence after the relationship is removed creates contradictory state that can confuse UI, duplicate review logic, analytics, and future migrations.

Suggested implementation: make `duplicateOfJobID == nil` imply `duplicateConfidence == nil` at every mutation boundary. Prefer a small domain helper or single service method for clearing duplicate metadata, then use it from manual unmarking, status changes, field updates, and recapture logic.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `unmarkDuplicate` clears both `duplicateOfJobID` and `duplicateConfidence`.
- [ ] #2 Any path that clears `duplicateOfJobID`, including recapture/reset-style paths, also clears `duplicateConfidence`.
- [ ] #3 Changing status away from `.duplicate` still clears duplicate metadata consistently.
- [ ] #4 Tests assert the invariant `duplicateOfJobID == nil` implies `duplicateConfidence == nil` for manual unmarking, status changes, field updates, and recapture where applicable.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
JobService.unmarkDuplicate now clears duplicateConfidence along with duplicateOfJobID (matching setStatus's invariant repair and updateJobFields); the recapture path in BackgroundStore also clears it. Covered by testUnmarkDuplicate_clearsLinkAndConfidence. Commit cc71925.
<!-- SECTION:FINAL_SUMMARY:END -->
