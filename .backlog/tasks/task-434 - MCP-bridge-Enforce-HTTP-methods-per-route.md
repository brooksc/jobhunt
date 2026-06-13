---
id: TASK-434
title: 'MCP bridge: Enforce HTTP methods per route'
status: To Do
assignee: []
created_date: '2026-06-13 05:45'
labels:
  - audit
  - server
  - mcp
dependencies: []
references:
  - server/swift/MCPBridgeRoutes.swift
  - mcp/swift/MCPHelpers.swift
  - tests/ServerTests/JobhuntServerTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`routeMCPRequest` validates the MCP token and then dispatches solely on `request.path`. Routes such as `/mcp/jobs/list`, `/mcp/jobs/get`, and `/mcp/snapshot` do not reject unexpected HTTP methods, so the route surface is looser than the MCP helper contract.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each `/mcp/*` route declares and enforces its accepted HTTP method or methods.
- [ ] #2 Unexpected methods return a stable error status such as 405 with a safe JSON error body.
- [ ] #3 Existing MCP helper calls continue to work with their intended method.
- [ ] #4 Server tests cover at least one read route and one write route rejecting an unexpected method.
<!-- AC:END -->
