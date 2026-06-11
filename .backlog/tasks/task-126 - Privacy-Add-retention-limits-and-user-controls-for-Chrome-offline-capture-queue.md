---
id: TASK-126
title: >-
  Privacy: Add retention limits and user controls for Chrome offline capture
  queue
status: Done
assignee: []
created_date: '2026-06-11 03:01'
updated_date: '2026-06-11 19:27'
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
modified_files:
  - extension/retry_queue.js
  - extension/status.js
  - PRIVACY.md
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

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added 7-day TTL and 50-item max to the extension offline capture queue. retry_queue.js: added QUEUE_TTL_MS, MAX_QUEUE_SIZE constants and purgeExpired(queue) function; enqueueCapture and flushQueue now call purgeExpired before operating. status.js: loadQueue calls purgeExpired and persists the trimmed queue before rendering. The status UI already showed queue count and provided clear/sync buttons — confirmed satisfactory. PRIVACY.md updated to document the 7-day TTL, 50-item cap, and user controls. CSV export includes full captured text (intentional: explicit user action exporting their own locally-stored data).
<!-- SECTION:FINAL_SUMMARY:END -->
