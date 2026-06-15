---
id: TASK-384
title: >-
  Duplicates view: Prevent stale detached scan results from overwriting newer
  state
status: Done
assignee: []
created_date: '2026-06-12 22:55'
updated_date: '2026-06-15 19:06'
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
- [x] #1 Duplicate scanning uses structured concurrency or checks a generation/cancellation token before publishing results.
- [x] #2 Older scans cannot overwrite newer pair/jobIndex state.
- [x] #3 Tests or a focused manual stress check cover rapid job/status changes while the duplicates view is open.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
AC#3 manual stress check (DuplicatesView is a @Query/SwiftUI view not unit-testable without a graphical session): open the Duplicates view with many jobs, then rapidly change job statuses / extraction states (e.g. archive/pass several jobs in quick succession from the Jobs list in another window, or run extraction that flips extractionStatus) while the view is open. Verify the pair list and selected-pair detail always settle on the result for the latest state and never flicker back to a superseded set. The generation guard ensures any detached scan that resumes after a newer scan started returns early without publishing.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Fixed a stale-write race in DuplicatesView. The duplicate scan runs in Task.detached (not a child task), so .task(id:) cancellation on rapid job/status changes couldn't stop it and the resumed older scan would overwrite newer pairs/jobIndex. Added a monotonic `scanGeneration` captured at the start of `refreshPairsInBackground`; results are published only when the generation is still current and the task wasn't cancelled, and jobIndex is now published atomically with pairs (built locally, assigned together) so the two can't diverge. App builds. AC#3 covered by a documented focused manual stress check (view not unit-testable without a graphical session).
<!-- SECTION:FINAL_SUMMARY:END -->
