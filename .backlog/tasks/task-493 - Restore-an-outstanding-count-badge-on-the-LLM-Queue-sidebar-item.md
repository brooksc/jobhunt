---
id: TASK-493
title: Restore an outstanding-count badge on the LLM Queue sidebar item
status: Done
assignee: []
created_date: '2026-06-18 19:17'
labels:
  - ux
  - queue
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The LLM Queue sidebar row showed no count of outstanding work; the user wants a live badge of jobs left to process that updates as the queue drains.

Fix: added a @Query for non-terminal LLMRequests (finishedAt == nil = queued + running) and badge the LLM Queue sidebar row with its count (hidden at 0), matching the Needs Action badge pattern. SwiftData @Query keeps it live.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 LLM Queue sidebar row shows a badge with the count of outstanding (queued+running) requests
- [ ] #2 The badge updates live as the queue processes and is hidden when zero
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added a live outstanding-work badge to the LLM Queue sidebar row: a @Query over non-terminal LLMRequests (finishedAt == nil) drives .badge(count), hidden at zero (same pattern as Needs Action). Updates automatically as the queue drains. Build-verified.
<!-- SECTION:FINAL_SUMMARY:END -->
