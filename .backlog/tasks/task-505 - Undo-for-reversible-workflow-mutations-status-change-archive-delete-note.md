---
id: TASK-505
title: 'Undo for reversible workflow mutations (status change, archive, delete-note)'
status: Done
assignee: []
created_date: '2026-06-19 01:12'
updated_date: '2026-06-19 01:23'
labels:
  - hig
  - ux
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
macOS HIG (7.4/7.5/13.4): reversible workflow actions should be undoable rather than confirmation-gated. Today only follow-up *completion* offers Undo (the actionable-toast pattern in `completeFollowUpWithUndo`). Status changes (`setStatus`), archive, and note deletion show a toast only on error — no undo on success.

Extend the existing ToastStore actionable-toast "Undo" pattern (NOT a full UndoManager) to:
- Status change in JobDetailView / JobsView context menu → "Status set to X" + Undo (restore previous status).
- Archive (single + batch) → "Archived" + Undo (restore prior status, since archive == setStatus(.archived)).
- Note delete (already added inline edit/delete) → "Note deleted" + Undo.

Keep the two-step Delete-job confirmation as-is (hard destructive). Reuse `reopenAction`-style restore methods on JobService.

Evidence: JobDetailView.swift:2085 (archive confirmationDialog, no undo), JobsView.swift archive batch, core/Services/JobService.swift setStatus (toast on error only).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Changing a job's status surfaces an actionable Undo toast that restores the previous status
- [x] #2 Archiving (single and batch) surfaces an Undo toast that restores the prior status
- [x] #3 Deleting a timeline note surfaces an Undo toast that restores it
- [x] #4 Implemented via the existing ToastStore action pattern, not UndoManager; fast gate tests pass
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Extended the ToastStore actionable-Undo pattern to the remaining reversible mutations. Status changes (detail StatusPickerButton + Jobs row context-menu "Set Status") now show "Status set to X" + Undo restoring the prior status; multi-target undo restores each job's own prior status and is skipped when nothing actually changed. Note delete shows "Note deleted" + Undo via new JobService.restoreNote, which re-inserts the note preserving original occurredAt/createdAt (timeline position unchanged) — covered by testRestoreNote_reinsertsWithPreservedTimestamps. Archive already had Undo (kept; refactored into the shared archiveJobs method). No UndoManager. Committed in de184cd. Fast gate green.
<!-- SECTION:FINAL_SUMMARY:END -->
