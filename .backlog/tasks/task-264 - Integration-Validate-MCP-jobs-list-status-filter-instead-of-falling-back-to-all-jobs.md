---
id: TASK-264
title: >-
  Integration: Validate MCP jobs-list status filter instead of falling back to
  all jobs
status: Done
assignee: []
created_date: '2026-06-12 02:56'
updated_date: '2026-06-12 03:13'
labels:
  - audit
  - integration
  - mcp
  - privacy
dependencies: []
references:
  - core/Services/JobService.swift
  - server/swift/MCPBridgeRoutes.swift
  - mcp/swift/MCPHelpers.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`JobService.listJobs(status:limit:)` filters only when the raw status parses; otherwise it returns unfiltered jobs. Through MCP, a typo in `status` can return a broader list than requested.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 MCP jobs-list returns `400` for invalid status values instead of falling back to unfiltered results.
- [ ] #2 Tests cover valid status, invalid status, omitted status, and limit clamping together.
- [ ] #3 Any non-MCP callers that intentionally use fallback behavior are separated from the MCP boundary validation.
<!-- AC:END -->
