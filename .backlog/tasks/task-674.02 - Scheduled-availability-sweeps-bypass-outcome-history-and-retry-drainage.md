---
id: TASK-674.02
title: Scheduled availability sweeps bypass outcome history and retry drainage
status: Done
assignee: []
created_date: '2026-08-21 20:26'
updated_date: '2026-08-22 03:37'
labels:
  - bug
  - availability
  - background
  - persistence
dependencies: []
references:
  - TASK-673
  - TASK-674
  - app/Shell/AppServices.swift
modified_files:
  - app/Shell/AppServices.swift
  - core/Services/AvailabilityChecker.swift
  - tests/CoreTests/AvailabilityCheckerTests.swift
parent_task_id: TASK-674
priority: high
type: bug
ordinal: 53000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Regression found during the 2026-08-21 code review. The scheduled automatic availability path receives a complete sweep but uses only its gone count for notification. It does not record per-job outcomes and does not hand deferred or transient failures to the availability backlog, so the normal recurring path leaves history stale and never redrives incomplete checks.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every completed scheduled sweep records all alive, gone, and unverified outcomes with its completion time
- [ ] #2 Retryable and deferred results from scheduled sweeps enter the same background drainage workflow as foreground results
- [ ] #3 A skipped or failed scheduled sweep does not write outcome history or seed retry work
- [ ] #4 Scheduled persistence and backlog seeding occur before any completion notification is emitted
- [ ] #5 Focused orchestration tests cover an alive result, a gone result, and a retryable unverified result
<!-- AC:END -->
