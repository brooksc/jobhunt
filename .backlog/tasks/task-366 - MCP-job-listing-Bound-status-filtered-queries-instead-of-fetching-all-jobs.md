---
id: TASK-366
title: 'MCP job listing: Bound status-filtered queries instead of fetching all jobs'
status: To Do
assignee: []
created_date: '2026-06-12 22:03'
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
- [ ] #1 Status-filtered MCP list requests are bounded without dropping eligible rows unexpectedly.
- [ ] #2 If needed, add denormalized raw status fields or cursor pagination to support efficient filtering.
- [ ] #3 Tests cover status-filtered list behavior with large mixed-status data.
<!-- AC:END -->
