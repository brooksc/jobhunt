---
id: TASK-193
title: 'Extension: Make offline queue mutations atomic'
status: To Do
assignee: []
created_date: '2026-06-11 23:46'
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
- [ ] #1 Queue enqueue, purge, and flush operations are serialized or otherwise made conflict-safe.
- [ ] #2 A capture enqueued during a flush cannot be dropped by the flush writeback.
- [ ] #3 Tests cover concurrent flush/enqueue behavior with deterministic fake storage.
<!-- AC:END -->
