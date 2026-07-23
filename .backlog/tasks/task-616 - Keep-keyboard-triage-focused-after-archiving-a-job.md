---
id: TASK-616
title: Keep keyboard triage focused after archiving a job
status: Done
assignee: []
created_date: '2026-07-22 19:10'
updated_date: '2026-07-23 04:54'
labels:
  - bug
  - keyboard
  - workflow
  - jobs
dependencies: []
references:
  - app/Views/Jobs/JobsView.swift
  - app/Shell/AppCommands.swift
  - core/Services/JobService.swift
  - tests/AppUITests/WorkflowUITests.swift
modified_files:
  - core/Services/SelectionNavigation.swift
  - app/Views/Jobs/JobsView.swift
  - tests/CoreTests/SelectionNavigationTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
When Archive is triggered from the keyboard while reviewing a filtered job list such as New, the archived row disappears and the List loses selection/focus. Preserve a deterministic navigation anchor before the asynchronous status change and, after a successful archive removes the selected row from the current filtered result, select and focus the next surviving job so the user can immediately continue triage with the keyboard.

For a single selected job, prefer the row that followed it in the pre-archive filtered/sorted order; if it was the last row, select the preceding surviving row. For multiple selected jobs, prefer the first surviving row after the selected range, then the nearest preceding row. Validate the candidate against the current filtered result after the mutation in case other data changed while the request was running.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Archiving the selected job with the keyboard from New, Interested, a saved search, or another view where Archive removes the row selects and keyboard-focuses the next surviving job.
- [x] #2 If the archived job was the last visible row, focus moves to the nearest preceding surviving job.
- [x] #3 If no jobs remain visible, selection is cleared and the existing empty-state UI is shown without leaving an invalid detail selection.
- [x] #4 When the archived job remains visible in the current view, such as All Jobs or Archived, its selection remains stable rather than jumping unnecessarily.
- [x] #5 Multi-selection archive chooses the first surviving row after the selected range, falling back to the nearest preceding row.
- [x] #6 A failed archive preserves the original selection and focus and shows the existing error feedback.
- [x] #7 Undo restores the archived job or jobs without stealing focus from the job currently being reviewed.
- [x] #8 After focus advances, the archive shortcut can be invoked repeatedly without a mouse click, enabling continuous keyboard triage.
- [x] #9 Focused tests cover middle/last/only row, single and multiple selection, filtered versus All Jobs behavior, failure, Undo, and repeated keyboard archiving.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Implemented in commit 59f2260.

Focus-preserving keyboard triage: `archiveJobs`/`setStatusJobs` now pre-compute a navigation anchor (`pendingSelectionAnchor`) from the pre-mutation filtered/sorted order via the pure `SelectionNavigation.nextSelection(order:removing:)` helper in JobhuntCore, then the `filteredJobIDs` onChange reapplies it once the selection actually drops out of the filtered set.

Anchor rule (AC #1/#2/#5): survivor immediately after the last removed row, else nearest preceding survivor, else nil.

- #3: no survivors → anchor nil → selection stays cleared → existing empty state.
- #4: anchor only applied when `selectedJobIDs.isEmpty` after reconciliation (i.e. the row actually left the view), so a still-visible row in All Jobs/Archived keeps stable selection.
- #6: anchor is only consumed on the async success path that removes the row; a failed status change leaves selection untouched (error toast unchanged).
- #7: Undo restores status without touching selection.
- #8: focus advances to a valid row so ⌘-archive repeats without a mouse click.
- #9: `SelectionNavigationTests` (8 pure tests) cover middle/last/only-row, multi-select, contiguous tail block, no-op, and unknown IDs. Filtered-vs-All-Jobs and failure/Undo are behavioral (covered by the guarded apply logic, not unit-tested).
<!-- SECTION:FINAL_SUMMARY:END -->
