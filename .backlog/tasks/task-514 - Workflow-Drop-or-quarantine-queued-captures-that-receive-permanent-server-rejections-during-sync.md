---
id: TASK-514
title: >-
  Workflow: Drop or quarantine queued captures that receive permanent server
  rejections during sync
status: To Do
assignee: []
created_date: '2026-06-19 01:31'
updated_date: '2026-07-21 22:59'
labels:
  - workflow
  - extension
  - capture-queue
dependencies: []
references:
  - extension/retry_queue.js
  - extension/service_worker.js
  - extension/status.js
  - extension/tests/test_retry_queue.js
  - extension/tests/test_service_worker_contract.js
  - server/swift/JobhuntServer.swift
priority: medium
ordinal: 8000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: Initial capture submission treats permanent 4xx responses (except 408/429) as non-retryable and does not enqueue them. However, `retry_queue.flushQueue` catches all sync errors and keeps failed items in the queue. If an already-queued capture later receives a permanent 400/403/413 from the app, the queue keeps retrying it and `status.js` reports "Could not reach Jobhunt," which is inaccurate.

Why this matters: Users can get stuck with unsyncable captures that look like temporary connectivity failures. This undermines the offline queue workflow and can hide validation or payload-size problems until the queue TTL expires or the user manually clears everything.

Suggested implementation: Preserve retry for network/5xx/408/429 failures, but classify permanent 4xx failures during flush. Remove them from the retry queue or move them to a visible failed/quarantine list with reason/status. Update the status page to distinguish unreachable app from permanently rejected captures.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Queued captures that receive permanent 4xx responses during sync are not retried indefinitely as ordinary queued items.
- [ ] #2 The capture queue/status UI clearly distinguishes temporary connectivity/server failures from permanently rejected captures.
- [ ] #3 Successful queued captures are still removed from the queue, and retryable failures remain queued.
- [ ] #4 Initial permanent rejection behavior remains unchanged: fresh captures are not enqueued for retry.
- [ ] #5 Extension tests cover queued-item permanent rejection during `flushQueue`/`flushCaptureQueue`, including status/result reporting.
<!-- AC:END -->
