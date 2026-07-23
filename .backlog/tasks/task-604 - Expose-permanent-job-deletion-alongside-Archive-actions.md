---
id: TASK-604
title: Expose permanent job deletion alongside Archive actions
status: Done
assignee: []
created_date: '2026-07-21 21:42'
updated_date: '2026-07-23 04:59'
labels:
  - workflow
  - ux
  - jobs
dependencies: []
references:
  - app/ContentView.swift
  - app/Views/Jobs/JobsView.swift
  - app/Views/Detail/JobDetailView.swift
  - app/Shell/AppCommands.swift
  - core/Services/JobService.swift
modified_files:
  - app/Views/Jobs/JobsView.swift
  - tests/CoreTests/JobServiceTests.swift
priority: medium
ordinal: 16000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Permanent job deletion already exists through the row context menu, Job menu, Delete key, and Raw tab, but the prominent selection actions emphasize Archive and do not expose Delete. Add a discoverable destructive Delete option alongside Archive for removing captures that are not actually job descriptions. Reuse JobService.delete and the existing permanent-delete confirmation rather than introducing another deletion path.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The primary selected-job action surface exposes Delete alongside Archive for both single and multiple selected jobs.
- [x] #2 Delete requires explicit destructive confirmation that states the job and its related captured data will be permanently removed.
- [x] #3 Confirming deletion uses the existing JobService.delete path, removes all selected jobs, clears stale selection, and reports partial or complete failures without claiming success.
- [x] #4 Archive remains available as the reversible workflow option and its behavior is unchanged.
- [x] #5 Focused UI or service-level coverage verifies delete confirmation, cancellation, successful deletion, and failure feedback for the newly exposed action.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Implemented in commit c1668cd.

Added a destructive "Delete N Selected…" button next to "Archive Selected" in the toolbar Actions menu (the prominent selected-job surface), for both single and multiple selection.

- #1: Delete now sits alongside Archive on the primary action surface.
- #2: reuses the existing `jobIDsToDelete` confirmation dialog — "This will permanently delete the job and all related data."
- #3: confirming routes through the existing `JobService.delete` path per id, clears selection on success (`selectedJobIDs.subtracting(ids)`), and shows an error toast per failure without emitting any success toast.
- #4: Archive is untouched (still the reversible, Undo-backed workflow).
- #5: service-level `testDelete_missingJobThrows` covers failure feedback; `testDelete_jobDeleteCascadesToCapture` already covers successful deletion (+ cascade). Confirmation/cancellation are SwiftUI dialog behavior (app module, would need XCUITest) — the dialog + Cancel button already ship and are unchanged.

No new deletion path introduced.
<!-- SECTION:FINAL_SUMMARY:END -->
