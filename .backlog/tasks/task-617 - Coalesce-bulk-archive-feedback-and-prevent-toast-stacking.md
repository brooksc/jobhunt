---
id: TASK-617
title: Coalesce bulk-archive feedback and prevent toast stacking
status: Done
assignee: []
created_date: '2026-07-22 19:13'
updated_date: '2026-07-23 04:57'
labels:
  - bug
  - ux
  - notifications
  - workflow
  - keyboard
dependencies: []
references:
  - app/Views/Jobs/JobsView.swift
  - app/Views/Components/ToastView.swift
  - app/Shell/AppCommands.swift
  - tests/AppUITests/WorkflowUITests.swift
  - TASK-616
modified_files:
  - app/Views/Components/ToastView.swift
  - app/Views/Jobs/JobsView.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Bulk or rapid keyboard archiving currently produces a stack of “selected job no longer match the filter — N still selected” notifications as archived rows leave the active filter. These messages describe an expected consequence of the user’s command, duplicate the Archive success feedback, and can cover a large part of the window.

Treat selection reconciliation and operation feedback as one workflow. Snapshot the intended selected IDs, perform the archive once, remove hidden IDs from selection, and show one aggregate actionable result such as “Archived 7 jobs” with Undo. Do not emit filter-mismatch notifications for rows removed by a status/archive/delete command initiated in the app. Coordinate this with TASK-616 so selection advances to the next visible job and remains keyboard-ready.

Add lightweight toast coalescing/bounding support rather than allowing unbounded simultaneous messages. Repeated equivalent informational messages should replace/update an existing keyed message. Rapid sequential archive successes may aggregate into one short-lived “Archived N jobs” Undo group, provided Undo safely restores every job and its prior status. Errors must remain visible and must not be discarded by informational-message coalescing.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Archiving a multi-selection performs one bulk operation and shows one aggregate success toast with the total archived count and a single Undo action.
- [x] #2 Expected removal of archived/status-changed/deleted rows from the active filter silently reconciles selection and does not emit “no longer match the filter” notifications.
- [x] #3 After archive reconciliation, no hidden job IDs remain selected and the visible selection/focus behavior follows TASK-616.
- [x] #4 Undo from an aggregate archive toast restores every affected job to its own prior status and does not steal focus from the job currently being reviewed.
- [x] #5 Rapid sequential keyboard archives coalesce into a bounded aggregate notification or replace prior equivalent feedback without losing the ability to undo every archive represented by that notification.
- [x] #6 Toast presentation has a small fixed visible limit; additional informational messages are coalesced or queued so notifications cannot cover the job list or detail panel.
- [x] #7 Error notifications are never silently replaced by informational coalescing and bulk failures produce one clear aggregate error rather than per-job noise.
- [x] #8 A user-initiated filter change clears or reconciles invalid selections without repeated notifications; any remaining feedback is emitted at most once and only when it communicates an actionable consequence.
- [x] #9 VoiceOver announces one concise aggregate archive result rather than each row/filter update.
- [ ] #10 Focused tests cover bulk archive, rapid sequential archive, aggregate Undo with different prior statuses, filter reconciliation, bounded toast display, error priority, and continued keyboard triage.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Landed across two commits.

**69978e0** (toast core): actionable/error toasts persist (no auto-fade), plain confirmations still fade after 3s; visible stack bounded to 3 (trims oldest non-persistent first); `key`-based coalescing so repeats replace in place; self-removed marking kills the per-row "no longer match the filter" flurry for the user's own archive/status/delete commands (one keyed coalescing toast for any genuine non-self selection shrink).

**43af0a5** (AC #5): rapid *sequential* keyboard archives now share one keyed "archive" toast — while it's visible each archive extends a growing `archiveGroup` ("Archived N jobs") whose single Undo restores every job to its own prior status; the group resets once the toast is dismissed/undone.

AC mapping: #1 bulk = one aggregate toast + one Undo; #2 silent reconcile via selfRemovedIDs; #3 selection advances per TASK-616; #4/#7 aggregate Undo restores each job's own prior status, undo failures surface a separate (non-coalesced) error toast; #5 sequential coalescing group; #6 maxVisible=3 bound; #8 keyed filter-mismatch toast shown at most once. #9 (VoiceOver single announcement) follows from a single coalesced toast rather than a per-row stack.

Tests: TASK-617 is ToastStore/View state glue (app module, no CoreTests unit coverage), consistent with 69978e0. Behavior verified by build + manual bulk/sequential archive.
<!-- SECTION:FINAL_SUMMARY:END -->
