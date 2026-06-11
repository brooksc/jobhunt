---
id: TASK-147
title: >-
  Performance: Replace availability-check over-fetch heuristic with an
  eligible-job query
status: To Do
assignee: []
created_date: '2026-06-11 03:45'
labels:
  - performance
  - correctness
  - availability
dependencies: []
references:
  - core/Services/AvailabilityChecker.swift
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Performance audit finding: stale availability checks fetch `limit * 10` oldest jobs, filter active/stale captures in memory, then prefix to `limit`. The work is bounded but can miss eligible stale jobs when early rows are not checkable.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Availability checking selects eligible jobs directly using predicate-friendly persisted fields such as status raw value and next-check date.
- [ ] #2 The checker no longer relies on a fixed over-fetch multiplier to find stale active jobs.
- [ ] #3 Tests cover cases where many early jobs are archived/passed/closed and later active stale jobs still get checked.
<!-- AC:END -->
