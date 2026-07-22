---
id: TASK-617
title: Coalesce bulk-archive feedback and prevent toast stacking
status: To Do
assignee: []
created_date: '2026-07-22 19:13'
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
- [ ] #1 Archiving a multi-selection performs one bulk operation and shows one aggregate success toast with the total archived count and a single Undo action.
- [ ] #2 Expected removal of archived/status-changed/deleted rows from the active filter silently reconciles selection and does not emit “no longer match the filter” notifications.
- [ ] #3 After archive reconciliation, no hidden job IDs remain selected and the visible selection/focus behavior follows TASK-616.
- [ ] #4 Undo from an aggregate archive toast restores every affected job to its own prior status and does not steal focus from the job currently being reviewed.
- [ ] #5 Rapid sequential keyboard archives coalesce into a bounded aggregate notification or replace prior equivalent feedback without losing the ability to undo every archive represented by that notification.
- [ ] #6 Toast presentation has a small fixed visible limit; additional informational messages are coalesced or queued so notifications cannot cover the job list or detail panel.
- [ ] #7 Error notifications are never silently replaced by informational coalescing and bulk failures produce one clear aggregate error rather than per-job noise.
- [ ] #8 A user-initiated filter change clears or reconciles invalid selections without repeated notifications; any remaining feedback is emitted at most once and only when it communicates an actionable consequence.
- [ ] #9 VoiceOver announces one concise aggregate archive result rather than each row/filter update.
- [ ] #10 Focused tests cover bulk archive, rapid sequential archive, aggregate Undo with different prior statuses, filter reconciliation, bounded toast display, error priority, and continued keyboard triage.
<!-- AC:END -->
