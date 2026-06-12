---
id: TASK-333
title: 'Export/backup tests: Cover restore behavior and CSV contract'
status: Done
assignee: []
created_date: '2026-06-12 20:06'
updated_date: '2026-06-12 20:58'
labels:
  - audit
  - tests
  - backup
  - restore
  - csv
dependencies: []
references:
  - tests/CoreTests/BackupServiceTests.swift
  - tests/CoreTests/JobServiceTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Current tests cover backup creation and basic CSV quoting/counts, but not restore replacement behavior, WAL/SHM cleanup, invalid schema rejection, pre-restore failures, exact CSV header order, or formula safety.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 BackupService restore tests cover successful replacement, failure behavior, companion cleanup, and invalid backup rejection.
- [ ] #2 CSV tests assert exact header names/order and formula-safety behavior, not only column count.
- [ ] #3 Regression tests fail against the current companion-file and formula-injection bugs.
<!-- AC:END -->
