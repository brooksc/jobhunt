---
id: TASK-514
title: >-
  Workflow: Drop or quarantine queued captures that receive permanent server
  rejections during sync
status: Done
assignee: []
created_date: '2026-06-19 01:31'
updated_date: '2026-08-09 20:10'
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
- [x] #1 Queued captures that receive permanent 4xx responses during sync are not retried indefinitely as ordinary queued items.
- [ ] #2 not verified (visual): the status page distinguishes temporary failures from permanent rejections — the message is built and the counts come from tested flush results, but the rendered page was not observed, since driving the UI is out of scope for this run.
- [x] #3 Successful queued captures are still removed from the queue, and retryable failures remain queued.
- [x] #4 Initial permanent rejection behavior remains unchanged: fresh captures are not enqueued for retry.
- [x] #5 Extension tests cover queued-item permanent rejection during flushQueue, including status/result reporting.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The classification already existed — `submitCapture` sets `error.permanent` for any 4xx except 408/429, which TASK-438 uses to avoid enqueueing a *fresh* refused capture. `flushQueue` simply ignored the flag and pushed every failure back onto the queue.

The result was wrong in two ways at once: an already-queued capture the app refuses (400 validation, 413 too large) retried forever, and the status page called it "Could not reach JobHunt" — sending the user to look for a closed app that was open and answering.

**Now:** permanent rejections move to a separate `jobhunt.rejectedCaptures` list carrying the status, the message and a timestamp, bounded to 20 (newest kept). `flushQueue` returns `{submitted, remaining, rejected}` and the status page reports rejections apart from unreachability, saying explicitly that the retry has stopped.

**Judgement call — keep rather than drop.** The task offered "remove them from the retry queue or move them to a visible failed list". Silently discarding a capture the user deliberately made is worse than showing a refused one, and the reason is exactly what makes a 413 or a validation failure fixable. Bounded so the list stays a diagnostic rather than becoming a second queue.

Criterion 4 needed no work: the fresh-capture path was already correct and is untouched.

**Tests** (6 new in `test_retry_queue.js`): rejected item leaves the queue; the reason and status are recorded; retryable failures still stay queued; successes still removed; all three outcomes separate correctly within a single flush; the rejected list is bounded and keeps the newest. Full extension suite: **107 passing**.

Criterion 2 is `not verified`: the message is assembled from tested counts, but the rendered status page was not observed.
<!-- SECTION:FINAL_SUMMARY:END -->
