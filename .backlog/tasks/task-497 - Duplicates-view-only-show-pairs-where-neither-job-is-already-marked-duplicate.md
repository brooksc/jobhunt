---
id: TASK-497
title: 'Duplicates view: only show pairs where neither job is already marked duplicate'
status: Done
assignee: []
created_date: '2026-06-18 21:53'
updated_date: '2026-06-18 21:53'
labels:
  - ux
  - duplicates
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The Duplicates review queue showed pairs even when one side was already marked `.duplicate` (resolved at ingest). Marking a job duplicate IS the resolution — the record must persist so the same URL-variation can't re-create a job — so a resolved pair shouldn't reappear for review.

Fix: exclude `.duplicate`-status jobs from the duplicate scan in both DuplicatesView and the sidebar badge count, so a pair only forms between two un-marked jobs. Empty state reworded to "No new duplicates to review." The sidebar badge already retriggers on status changes (duplicateRefreshID hashes job.status), so it stays consistent.

Files: app/Views/Duplicates/DuplicatesView.swift, app/Shell/Sidebar.swift.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A pair where either job is already marked .duplicate is not shown in the Duplicates view
- [x] #2 The Duplicates sidebar badge counts only un-marked pairs and updates when a job is marked duplicate
- [x] #3 When all detected pairs have a marked side, the view shows the empty state ('No new duplicates to review.')
<!-- AC:END -->



## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
DuplicatesView and the sidebar duplicate-count both drop jobs with status == .duplicate from the snapshot set before running DuplicateDetector, so a pair can only form between two still-un-marked jobs — a resolved (marked) duplicate no longer clutters the review queue, while its record persists to block URL-variation re-adds. Empty state reworded to "No new duplicates to review." The sidebar badge's refresh signal already hashes job.status, so marking a job duplicate recomputes the count immediately. Build-verified; DuplicateDetector core (and its tests) unchanged.
<!-- SECTION:FINAL_SUMMARY:END -->
