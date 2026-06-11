---
id: TASK-145
title: 'Performance: Make LLM queue processing and bulk mutations batch-oriented'
status: Done
assignee: []
created_date: '2026-06-11 03:45'
updated_date: '2026-06-11 19:54'
labels:
  - performance
  - queue
  - swiftdata
dependencies: []
references:
  - core/LLM/QueueActor.swift
  - core/Services/JobService.swift
  - core/Services/BackgroundStore.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Performance audit finding: queue processing fetches all LLM requests each batch and filters queued requests in memory; enqueue and bulk job operations often perform one fetch/save per row or whole-table updates.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Queue processing fetches only queued work using predicate-friendly status/type fields and `fetchLimit`.
- [ ] #2 Bulk enqueue, bulk status, bulk extraction reset, and mark-expired operations fetch target records in batches and save once per operation where practical.
- [ ] #3 Old succeeded/failed queue history is pruned, archived, or paged so current processing is independent of total history size.
- [ ] #4 Tests cover bulk operations for correctness and reduced save/query behavior.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
BackgroundStore: added deleteFiltered(_:predicate:where:) for predicate-narrowed fetch + in-memory filter + delete. QueueActor: enqueue(jobIDs:) now does one batch fetch of all jobs + one insertBatch save instead of N fetch+save pairs. fetchQueuedRequests now sets fetchLimit=1000 to bound the scan. requeueRunningOnLaunch now calls pruneFinishedRequests() at startup. New pruneFinishedRequests(olderThan:days) deletes terminal (succeeded/failed/cancelled/retryExhausted) records older than 30 days, using a finishedAt!=nil predicate to exclude queued/running, with date+status check in Swift. JobService: setStatusBulk uses #Predicate{ids.contains($0.id)} for a single fetch+save. markExpired same — drops the whole-table scan. Tests: testEnqueueBatch_createsOneRequestPerJob, testSetStatusBulk_updatesAllSpecifiedJobs, testMarkExpired_updatesOnlySpecifiedJobs, testPruneFinishedRequests_removesOldTerminalRecords — all 4 pass alongside full CoreTests suite.
<!-- SECTION:FINAL_SUMMARY:END -->
