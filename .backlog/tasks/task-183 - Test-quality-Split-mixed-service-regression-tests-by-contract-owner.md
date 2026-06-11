---
id: TASK-183
title: 'Test quality: Split mixed service regression tests by contract owner'
status: Done
assignee: []
created_date: '2026-06-11 22:18'
updated_date: '2026-06-11 22:36'
labels:
  - audit
  - tests
  - maintainability
dependencies: []
references:
  - tests/CoreTests/JobServiceTests.swift
  - tests/CoreTests/SettingsStoreTests.swift
  - tests/CoreTests/ResumeServiceTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`JobServiceTests.swift` has grown into a mixed-concern regression file covering ingestion, CSV export, queue enqueue behavior, BackgroundStore not-found behavior, site service behavior, retention, and scheduling. Split these into focused files by service/contract so failures localize quickly and future tests have an obvious home.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 BackgroundStore-specific tests live in a BackgroundStore-focused test file.
- [ ] #2 SiteService-specific tests live in a SiteService-focused test file.
- [ ] #3 JobServiceTests is reduced to JobService-owned behavior with shared fixture helpers where useful.
<!-- AC:END -->
