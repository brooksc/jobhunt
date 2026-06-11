---
id: TASK-193
title: 'Extension: Make offline queue mutations atomic'
status: Done
assignee: []
created_date: '2026-06-11 23:46'
updated_date: '2026-06-11 23:56'
labels:
  - extension
  - capture
  - reliability
  - audit
dependencies: []
references:
  - extension/retry_queue.js
  - extension/service_worker.js
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The Chrome extension retry queue performs independent read-modify-write cycles for enqueue and flush operations. If a queue flush and a new capture overlap, the flush can overwrite the newly enqueued item with its stale remaining queue snapshot.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Queue enqueue, purge, and flush operations are serialized or otherwise made conflict-safe.
- [x] #2 A capture enqueued during a flush cannot be dropped by the flush writeback.
- [x] #3 Tests cover concurrent flush/enqueue behavior with deterministic fake storage.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added a `withLock` promise-chaining mutex to retry_queue.js. Both `enqueueCapture` and `flushQueue` now acquire the lock before their read-modify-write cycle, so they serialize. Added `retry_queue: atomicity` test that fires a flush and an enqueue concurrently and asserts the enqueued item survives the flush writeback. All 41 extension tests pass.
<!-- SECTION:FINAL_SUMMARY:END -->
