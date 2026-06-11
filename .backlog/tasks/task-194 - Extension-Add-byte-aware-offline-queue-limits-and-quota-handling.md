---
id: TASK-194
title: 'Extension: Add byte-aware offline queue limits and quota handling'
status: To Do
assignee: []
created_date: '2026-06-11 23:47'
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
- [ ] #1 Offline queue enforces a documented byte budget per capture and for the total queue.
- [ ] #2 Quota or storage failures produce a durable user-visible status instead of silently losing the capture.
- [ ] #3 Tests cover oversized payloads and storage quota failure behavior.
<!-- AC:END -->
