---
id: TASK-197
title: 'Extension: Preserve pending note context until capture succeeds'
status: Done
assignee: []
created_date: '2026-06-11 23:47'
updated_date: '2026-06-12 00:01'
labels:
  - extension
  - capture
  - notes
  - reliability
  - audit
dependencies: []
references:
  - extension/service_worker.js
  - extension/note.js
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The note capture path removes pending note state before capture and submission complete. A transient injection or capture failure can lose the association between the note window and the intended source tab.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Pending note tab state is cleared only after successful capture or is recoverable after retryable failure.
- [x] #2 The note window surfaces enough failure detail for the user to retry or correct the issue.
- [x] #3 Tests cover capture failure after note submission without losing pending context.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Moved `chrome.storage.session.remove("pendingNoteTabId")` to after `captureTabPayload` and `submitOrQueue` both succeed in service_worker.js. On failure the context is preserved for retry. note.js now includes the error detail in the failure message ("Could not save: …. Try again.") and keeps the window open. Added 3 contract tests: clears on success, preserves on injection failure, returns error detail. All 62 extension tests pass.
<!-- SECTION:FINAL_SUMMARY:END -->
