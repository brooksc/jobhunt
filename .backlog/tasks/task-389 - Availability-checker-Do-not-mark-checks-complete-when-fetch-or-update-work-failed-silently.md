---
id: TASK-389
title: >-
  Availability checker: Do not mark checks complete when fetch or update work
  failed silently
status: To Do
assignee: []
created_date: '2026-06-12 22:58'
labels:
  - audit
  - error-handling
  - availability
dependencies: []
references:
  - core/Services/AvailabilityChecker.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
AvailabilityChecker returns zero-count results on fetch failure and `maybeRunStaleCheck` records the last-check timestamp afterward. This can suppress future checks for the interval even though no valid check ran. Per-job update/event/notification errors are also silently skipped.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Fetch failures are returned or recorded as failures rather than zero-success checks.
- [ ] #2 Last-check timestamps are updated only after a valid check pass or with a separate failed-at timestamp.
- [ ] #3 Per-job marking/event/notification failures are counted and exposed in the check result.
- [ ] #4 Tests cover fetch failure interval behavior and partial per-job failures.
<!-- AC:END -->
