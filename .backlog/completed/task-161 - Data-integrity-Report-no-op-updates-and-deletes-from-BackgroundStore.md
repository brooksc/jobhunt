---
id: TASK-161
title: 'Data integrity: Report no-op updates and deletes from BackgroundStore'
status: Done
assignee: []
created_date: '2026-06-11 20:56'
updated_date: '2026-06-11 21:26'
labels:
  - audit
  - data-integrity
  - service-contract
dependencies: []
references:
  - core/Services/BackgroundStore.swift
  - core/Services/JobService.swift
  - core/Services/SiteService.swift
  - core/Services/ResumeService.swift
modified_files:
  - core/Services/BackgroundStore.swift
  - core/Services/JobService.swift
  - core/Services/SiteService.swift
  - tests/CoreTests/JobServiceTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`BackgroundStore.update` and `BackgroundStore.delete` save successfully even when no rows match. Service methods that target a specific ID therefore cannot tell success from a stale ID, including job actions, site state changes, and job deletes. Return affected counts or add updateOne/deleteOne helpers, then update services that should throw not-found errors.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Store APIs used for single-record mutations can report zero matches.
- [ ] #2 Services that target a required ID throw or return an explicit not-found result when no row is affected.
- [ ] #3 Tests cover at least job action completion, site state update, and job deletion for missing IDs.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added `BackgroundStoreError.notFound`, `updateOne`, and `deleteOne` to BackgroundStore. Updated `JobService.setStatus`, `delete(jobID:)` and `SiteService.updateSite`, `deleteSite`, `setSiteState` to use them. Five tests cover not-found detection for job actions and site mutations. Also removed a stale test line that was a silent no-op under the old silent-update behavior.
<!-- SECTION:FINAL_SUMMARY:END -->
