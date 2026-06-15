---
id: TASK-434
title: 'MCP bridge: Enforce HTTP methods per route'
status: Done
assignee: []
created_date: '2026-06-13 05:45'
updated_date: '2026-06-15 18:28'
labels:
  - audit
  - server
  - mcp
dependencies: []
references:
  - server/swift/MCPBridgeRoutes.swift
  - mcp/swift/MCPHelpers.swift
  - tests/ServerTests/JobhuntServerTests.swift
modified_files:
  - server/swift/MCPBridgeRoutes.swift
  - tests/ServerTests/JobhuntServerTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`routeMCPRequest` validates the MCP token and then dispatches solely on `request.path`. Routes such as `/mcp/jobs/list`, `/mcp/jobs/get`, and `/mcp/snapshot` do not reject unexpected HTTP methods, so the route surface is looser than the MCP helper contract.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Each `/mcp/*` route declares and enforces its accepted HTTP method or methods.
- [x] #2 Unexpected methods return a stable error status such as 405 with a safe JSON error body.
- [x] #3 Existing MCP helper calls continue to work with their intended method.
- [x] #4 Server tests cover at least one read route and one write route rejecting an unexpected method.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
routeMCPRequest now enforces POST for all /mcp/* routes (a single guard after the token check) — every MCP tool call is a POST per the helper contract (MCPHelpers sets httpMethod="POST" for all routes), so a blanket POST-only rule matches the contract exactly (AC#1). Non-POST returns 405 + the standard JSON error body (AC#2). Existing helper calls (all POST) are unaffected (AC#3). Test testMCPRoute_getMethodRejectedWith405 sends GET to a read route (/mcp/jobs/list) and a write route (/mcp/jobs/update), both 405 (AC#4).
<!-- SECTION:FINAL_SUMMARY:END -->
