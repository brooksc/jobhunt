---
id: TASK-366
title: 'MCP job listing: Bound status-filtered queries instead of fetching all jobs'
status: Done
assignee: []
created_date: '2026-06-12 22:03'
updated_date: '2026-06-15 19:13'
labels:
  - audit
  - performance
  - mcp
  - swiftdata
dependencies: []
references:
  - core/Services/JobService.swift
  - server/swift/MCPBridgeRoutes.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
JobService.listJobs(status:limit:) omits fetchLimit for status-filtered calls because SwiftData enum predicates are not supported, so filtered MCP requests can materialize all jobs.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Status-filtered MCP list requests are bounded without dropping eligible rows unexpectedly.
- [x] #2 If needed, add denormalized raw status fields or cursor pagination to support efficient filtering.
- [x] #3 Tests cover status-filtered list behavior with large mixed-status data.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Bounded `JobService.listJobs(status:limit:)` status-filtered path with cursor-style paging. Previously it fetched all jobs (no fetchLimit, since SwiftData can't predicate on the JobStatus enum), sorted, and filtered in memory — unbounded. Now it pages newest-first in chunks of max(limit,200) using fetchLimit+fetchOffset, filters each page, and stops once `limit` matches accumulate; peak memory is one page and the common case exits after page 1. Added a stable `id` sort tiebreaker so page boundaries can't skip/duplicate rows sharing a createdAt. Chose paging over a denormalized statusRaw column to avoid a Job schema migration + backfill window during which old rows would be dropped from filtered results (AC#1 "without dropping eligible rows"). AC#3: new test inserts 255 mixed-status rows where matches sort past the first page, asserting they're still found, limit bounding, zero-match → empty, and limit==0 → empty. Full CoreTests/JobServiceTests green.
<!-- SECTION:FINAL_SUMMARY:END -->
