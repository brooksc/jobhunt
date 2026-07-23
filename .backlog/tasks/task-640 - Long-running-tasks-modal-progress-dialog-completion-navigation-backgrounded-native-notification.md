---
id: TASK-640
title: >-
  Long-running tasks: modal progress dialog + completion navigation +
  backgrounded native notification
status: Done
assignee: []
created_date: '2026-07-23 02:38'
labels:
  - ux
  - jobs
  - notifications
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The availability check and duplicate scan ran with no visibility (a silent ~minute) and only a menu-label change. Now they show a modal progress dialog (determinate n/total for the availability check via a findGoneJobs progress callback; indeterminate spinner for the single-shot duplicate scan) with a Cancel. On completion they take the user to the result: availability → nothing gone shows a message, some gone opens the expired-confirmation sheet; duplicates → nothing to review shows a message, otherwise navigates to the Duplicates screen. If Jobhunt wasn't frontmost when the task finished, a native macOS notification fires so it isn't missed. Reusable TaskProgressModel/TaskProgressDialog for other long tasks lacking visibility.

Paired with the toast changes (TASK-617 follow-up): actionable/error toasts now persist until dismissed, the stack is bounded, and the bulk-archive filter-mismatch flurry is suppressed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Availability check shows a modal progress dialog with a live n/total count and Cancel
- [ ] #2 Duplicate scan shows a modal spinner with Cancel
- [ ] #3 On completion the user is taken to the result (expired sheet / Duplicates screen) or shown a clear 'nothing found' message
- [ ] #4 Cancel stops the task and leaves data untouched
- [ ] #5 A native notification fires only when the app is not frontmost on completion
<!-- AC:END -->
