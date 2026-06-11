---
id: TASK-194
title: 'Extension: Add byte-aware offline queue limits and quota handling'
status: Done
assignee: []
created_date: '2026-06-11 23:47'
updated_date: '2026-06-11 23:57'
labels:
  - extension
  - capture
  - storage
  - reliability
  - audit
dependencies: []
references:
  - extension/retry_queue.js
  - extension/capture.js
  - extension/service_worker.js
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The extension stores full capture payloads in chrome.storage.local with only an item-count cap. Large visible_text or selected_text payloads can exceed storage quota, causing enqueue to fail and the capture to be lost behind a transient error badge.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Offline queue enforces a documented byte budget per capture and for the total queue.
- [x] #2 Quota or storage failures produce a durable user-visible status instead of silently losing the capture.
- [x] #3 Tests cover oversized payloads and storage quota failure behavior.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added MAX_ITEM_BYTES (100KB) and MAX_QUEUE_BYTES (4MB) constants to retry_queue.js. `enqueueCapture` now trims `visible_text` via binary-search to fit the per-item limit (preserving all other fields including selected_text), enforces the total queue byte budget, and catches chrome.storage quota errors — returning `{error:"quota"}` or `{error:"storage_quota"}` respectively. service_worker.js now checks for the error field and shows a red ERR badge. 4 new tests added; all 45 extension tests pass.
<!-- SECTION:FINAL_SUMMARY:END -->
