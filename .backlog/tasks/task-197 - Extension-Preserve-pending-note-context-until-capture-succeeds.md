---
id: TASK-197
title: 'Extension: Preserve pending note context until capture succeeds'
status: To Do
assignee: []
created_date: '2026-06-11 23:47'
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
- [ ] #1 Pending note tab state is cleared only after successful capture or is recoverable after retryable failure.
- [ ] #2 The note window surfaces enough failure detail for the user to retry or correct the issue.
- [ ] #3 Tests cover capture failure after note submission without losing pending context.
<!-- AC:END -->
