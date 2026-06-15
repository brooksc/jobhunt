---
id: TASK-438
title: >-
  Extension queue: Classify permanent capture failures instead of retrying
  forever
status: Done
assignee: []
created_date: '2026-06-13 18:25'
updated_date: '2026-06-15 18:32'
labels:
  - audit
  - extension
  - queue
  - ux
dependencies: []
references:
  - extension/service_worker.js
  - extension/retry_queue.js
  - extension/status.js
modified_files:
  - extension/service_worker.js
  - extension/tests/test_service_worker_contract.js
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`submitOrQueue` enqueues a capture on any submit failure. That includes permanent server responses such as validation errors, authorization failures, or oversized payloads. The offline queue then repeatedly retries bad payloads until TTL expiry while the UI reports a generic connectivity-style failure.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Capture submission distinguishes retryable failures from permanent failures using HTTP status and/or structured error codes.
- [x] #2 Permanent failures are not kept in the retry queue indefinitely; they surface a clear user-facing status and preserve enough context for troubleshooting or export where appropriate.
- [x] #3 Retryable network/server-unavailable failures continue to queue and sync later.
- [x] #4 The queue UI reports permanent failures differently from 'Mac app not reachable'.
- [x] #5 Add service-worker and retry-queue tests for at least one retryable failure and one permanent 400/413-style failure.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
submitCapture now tags a non-ok response with err.status and err.permanent (4xx except 408/429 → permanent; 5xx/network → retryable) (AC#1). submitOrQueue no longer queues permanent failures — it shows an ERR badge and returns {queued:false, permanent:true, status} so the caller/UI can report it distinctly from the queued/connectivity state (AC#2/#4); retryable failures still enqueue and sync via flushQueue (AC#3). Tests: a 413 capture is not queued, a 503 is queued (AC#5). This also satisfies TASK-435 AC#4 (extension treats the server's 413 as permanent). Full extension suite green (65/65).
<!-- SECTION:FINAL_SUMMARY:END -->
