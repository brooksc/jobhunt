---
id: TASK-005
title: Add extension retry queue and status feedback
status: Done
assignee: []
created_date: '2026-05-27 04:35'
updated_date: '2026-05-31 04:46'
labels:
  - m2-extension
  - extension
  - reliability
dependencies:
  - TASK-004
modified_files:
  - extension/service_worker.js
  - extension/retry_queue.js
  - tests/extension/retry_queue_test.mjs
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Make capture reliable when the local service is unavailable. Failed submissions should be stored locally and retried later while preserving the one-click default workflow.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 If the local service is unavailable a capture is saved to extension local storage instead of being lost
- [x] #2 Queued captures are retried on later capture attempts
- [x] #3 Successful saves duplicates queued saves and failures produce clear lightweight badge or icon feedback
- [x] #4 The extension avoids showing a notification for every successful save
- [x] #5 Manual verification covers service unavailable then service restored behavior
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Add a small service-worker retry queue backed by chrome.storage.local. On capture attempts, submit queued captures first, queue the current payload if the local API is unavailable, and use action badge text/color for saved duplicate queued and failure states without success notifications.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added retry and lightweight status feedback to the extension service worker. Failed submissions are queued in extension local storage, queued captures are retried on later capture attempts, and the toolbar badge reports OK DUP Q or ERR without success notifications.
<!-- SECTION:FINAL_SUMMARY:END -->
