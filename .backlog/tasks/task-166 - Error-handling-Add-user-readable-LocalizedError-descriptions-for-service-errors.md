---
id: TASK-166
title: >-
  Error handling: Add user-readable LocalizedError descriptions for service
  errors
status: To Do
assignee: []
created_date: '2026-06-11 21:42'
labels:
  - audit
  - error-handling
  - ux
dependencies: []
references:
  - core/Services/JobService.swift
  - core/Services/SiteService.swift
  - core/Settings/KeychainStore.swift
  - core/Util/JSONRepair.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Core service error enums such as `JobServiceError`, `SiteServiceError`, `KeychainError`, and `JSONRepairError` currently conform only to `Error`. Views that display `error.localizedDescription` can show generic Swift error text instead of actionable messages. Add `LocalizedError` conformance with safe, user-readable descriptions and tests for representative cases.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Service errors used by UI flows have `LocalizedError.errorDescription` values that are specific and user-readable.
- [ ] #2 Descriptions do not leak raw sensitive payloads or credentials.
- [ ] #3 Tests assert representative localized descriptions for job, site, keychain, and JSON repair errors.
<!-- AC:END -->
