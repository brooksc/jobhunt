---
id: TASK-616
title: Keep keyboard triage focused after archiving a job
status: To Do
assignee: []
created_date: '2026-07-22 19:10'
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
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
When Archive is triggered from the keyboard while reviewing a filtered job list such as New, the archived row disappears and the List loses selection/focus. Preserve a deterministic navigation anchor before the asynchronous status change and, after a successful archive removes the selected row from the current filtered result, select and focus the next surviving job so the user can immediately continue triage with the keyboard.

For a single selected job, prefer the row that followed it in the pre-archive filtered/sorted order; if it was the last row, select the preceding surviving row. For multiple selected jobs, prefer the first surviving row after the selected range, then the nearest preceding row. Validate the candidate against the current filtered result after the mutation in case other data changed while the request was running.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Archiving the selected job with the keyboard from New, Interested, a saved search, or another view where Archive removes the row selects and keyboard-focuses the next surviving job.
- [ ] #2 If the archived job was the last visible row, focus moves to the nearest preceding surviving job.
- [ ] #3 If no jobs remain visible, selection is cleared and the existing empty-state UI is shown without leaving an invalid detail selection.
- [ ] #4 When the archived job remains visible in the current view, such as All Jobs or Archived, its selection remains stable rather than jumping unnecessarily.
- [ ] #5 Multi-selection archive chooses the first surviving row after the selected range, falling back to the nearest preceding row.
- [ ] #6 A failed archive preserves the original selection and focus and shows the existing error feedback.
- [ ] #7 Undo restores the archived job or jobs without stealing focus from the job currently being reviewed.
- [ ] #8 After focus advances, the archive shortcut can be invoked repeatedly without a mouse click, enabling continuous keyboard triage.
- [ ] #9 Focused tests cover middle/last/only row, single and multiple selection, filtered versus All Jobs behavior, failure, Undo, and repeated keyboard archiving.
<!-- AC:END -->
