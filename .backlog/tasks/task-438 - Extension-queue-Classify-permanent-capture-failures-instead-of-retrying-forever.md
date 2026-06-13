---
id: TASK-438
title: >-
  Extension queue: Classify permanent capture failures instead of retrying
  forever
status: To Do
assignee: []
created_date: '2026-06-13 18:25'
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
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`submitOrQueue` enqueues a capture on any submit failure. That includes permanent server responses such as validation errors, authorization failures, or oversized payloads. The offline queue then repeatedly retries bad payloads until TTL expiry while the UI reports a generic connectivity-style failure.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Capture submission distinguishes retryable failures from permanent failures using HTTP status and/or structured error codes.
- [ ] #2 Permanent failures are not kept in the retry queue indefinitely; they surface a clear user-facing status and preserve enough context for troubleshooting or export where appropriate.
- [ ] #3 Retryable network/server-unavailable failures continue to queue and sync later.
- [ ] #4 The queue UI reports permanent failures differently from 'Mac app not reachable'.
- [ ] #5 Add service-worker and retry-queue tests for at least one retryable failure and one permanent 400/413-style failure.
<!-- AC:END -->
