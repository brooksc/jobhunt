---
id: TASK-126
title: >-
  Privacy: Add retention limits and user controls for Chrome offline capture
  queue
status: To Do
assignee: []
created_date: '2026-06-11 03:01'
labels:
  - privacy
  - extension
  - retention
  - offline-queue
dependencies: []
references:
  - extension/retry_queue.js
  - extension/status.html
  - extension/status.js
  - extension/export_csv.js
  - PRIVACY.md
  - .backlog/tasks/task-005 - Add-extension-retry-queue-and-status-feedback.md
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The extension offline queue stores full capture payloads in chrome.storage.local and can expose or retain selected text, visible text, and structured page data longer than needed. Add explicit retention limits and clearer user controls for queued capture data.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Queued capture storage has a bounded TTL and maximum count or size limit.
- [ ] #2 Expired or excess queued payloads are purged deterministically before retry/export/status display.
- [ ] #3 The extension status UI clearly shows queued capture count and provides a way to clear queued captures.
- [ ] #4 CSV/export behavior avoids accidentally exposing full captured text unless the user explicitly chooses that export scope.
- [ ] #5 Privacy documentation describes offline queued capture retention and user controls.
<!-- AC:END -->
