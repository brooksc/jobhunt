---
id: TASK-203
title: 'MCP: Clamp jobs list limit and avoid fetch-all pagination'
status: To Do
assignee: []
created_date: '2026-06-12 00:17'
labels:
  - mcp
  - server
  - performance
  - api
  - audit
dependencies: []
references:
  - server/swift/MCPBridgeRoutes.swift
  - core/Services/JobService.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The MCP jobs list route accepts arbitrary limit values and JobService.listJobs fetches all jobs before applying prefix(limit). Large datasets or large requested limits can make a simple MCP call unexpectedly expensive.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 MCP jobs/list clamps limit to a documented safe range.
- [ ] #2 Job listing avoids fetching every row when a bounded page is requested, where SwiftData supports it.
- [ ] #3 Tests cover negative, zero, default, and excessive limit values.
<!-- AC:END -->
