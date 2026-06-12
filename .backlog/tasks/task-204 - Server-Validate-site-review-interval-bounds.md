---
id: TASK-204
title: 'Server: Validate site review interval bounds'
status: Done
assignee: []
created_date: '2026-06-12 00:17'
updated_date: '2026-06-12 02:16'
labels:
  - server
  - sites
  - validation
  - audit
dependencies: []
references:
  - server/swift/JobhuntServer.swift
  - core/Services/SiteService.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The /site-reviews route passes interval_days directly into SiteService scheduling. Negative or extremely large values can create nonsensical review dates.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Site review intervals must be positive and within a documented maximum.
- [ ] #2 Invalid interval_days values return clear validation errors.
- [ ] #3 Service-level tests cover negative, zero, valid, and excessive interval values.
<!-- AC:END -->
