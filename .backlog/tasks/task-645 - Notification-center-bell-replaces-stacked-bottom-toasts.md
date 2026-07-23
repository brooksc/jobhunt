---
id: TASK-645
title: Notification center (bell) replaces stacked bottom toasts
status: Done
assignee: []
created_date: '2026-07-23 20:34'
updated_date: '2026-07-23 20:34'
labels:
  - ux
  - notifications
  - workflow
dependencies: []
references:
  - app/Views/Components/ToastView.swift
  - app/Views/Components/NotificationCenterView.swift
  - app/ContentView.swift
  - app/Views/Jobs/JobsView.swift
modified_files:
  - app/Views/Components/ToastView.swift
  - app/Views/Components/NotificationCenterView.swift
  - app/ContentView.swift
  - app/Views/Jobs/JobsView.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The bottom-anchored toast stack was poor UX: full-width persistent toasts obscured the last job row, actionable (Undo) toasts required manual dismissal, and plain confirmations vanished too fast. Replace it with a notification center behind a bell icon in the toolbar, plus a single brief transient toast for immediacy. Supersedes the persistent-stack + bounding behavior from TASK-617.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A bell icon in the top toolbar opens a notification center popover listing actionable + error notifications newest-first, each with its inline action (Undo) and a relative time, plus Clear All
- [x] #2 At most one compact, auto-fading transient toast shows at a time (bottom-trailing), so a burst never covers the job list
- [x] #3 Actionable/error notifications persist in the bell until undone, dismissed, or cleared; plain info confirmations are transient-only
- [x] #4 Rapid similar actions (archive, status change) coalesce into one bell entry ('Archived N jobs' / 'Updated N jobs') with a combined Undo-all
- [x] #5 Errors are shown in the bell (tinted) and still feed the Debug tab's recent-errors list
- [x] #6 The bell badges (bell.badge) when there are notifications
<!-- AC:END -->



## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ToastStore is now a notification center: one shared store holds a durable bell inbox (actionable + error notifications, newest-first) and a single transient toast. show(...) keeps its old signature (+ optional itemCount/groupMessage) so all ~90 call sites are unchanged; only actionable/error notifications are stored in the bell, plain info is transient-only. Repeated same-key actions within a 30s window coalesce into one entry with a combined Undo-all, driven by itemCount + groupMessage. The corner overlay shows at most one auto-fading toast (bottom-trailing, capped width) so a burst can't cover the list. A bell toolbar item (bell/bell.badge, orange when an error is present) opens NotificationCenterView (relative times, inline Undo, Clear All). JobsView's archive/status actions were simplified to use store coalescing (dropped the TASK-617 archiveGroup/ArchivedJob machinery); a shared static restore(...) is the Undo body. Builds + fast gate green.

Not done (deliberate): no unit tests — this is app-module @Observable/view glue (consistent with the rest of the toast work); verified by build + manual. Bell inbox has no auto-expiry (cleared via Clear All / per-item / undo).
<!-- SECTION:FINAL_SUMMARY:END -->
