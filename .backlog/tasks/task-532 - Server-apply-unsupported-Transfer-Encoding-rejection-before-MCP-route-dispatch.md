---
id: TASK-532
title: >-
  Server: apply unsupported Transfer-Encoding rejection before MCP route
  dispatch
status: To Do
assignee: []
created_date: '2026-06-19 04:51'
labels:
  - audit
  - security
  - server
  - mcp
  - http
dependencies: []
references:
  - server/swift/JobhuntServer.swift
  - server/swift/MCPBridgeRoutes.swift
  - server/swift/HTTPRequest.swift
  - tests/ServerTests/JobhuntServerTests.swift
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: `JobhuntServer.routeRequest` dispatches `/mcp/*` requests to `routeMCPRequest` before the shared `Transfer-Encoding` rejection check. Completed work added a global unsupported-transfer-encoding guard for normal routes, but MCP routes can still return route-specific errors such as invalid JSON instead of the explicit unsupported-framing error.

Why this matters: request framing policy should be uniform across the local HTTP surface. MCP routes are authenticated, but they still share the same parser. Letting one route family bypass the framing guard weakens the invariant and can hide malformed/chunked requests behind misleading application-layer errors.

Suggested implementation: move the `Transfer-Encoding` rejection ahead of MCP routing, or enforce it in the parser before route dispatch. Add a parser-level or direct `routeRequest` test that constructs an `HTTPRequest` with `transfer-encoding` for an MCP path and asserts the explicit 400 unsupported-framing response.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 All routes, including `/mcp/*`, reject requests carrying `Transfer-Encoding` before body decoding or route-specific validation.
- [ ] #2 The response for unsupported transfer encoding is consistent across extension, health, and MCP route families.
- [ ] #3 Existing MCP token/method checks remain unchanged for normally framed requests.
- [ ] #4 Focused tests cover an MCP request with `transfer-encoding: chunked` and a normal MCP request without that header.
- [ ] #5 The completed TASK-478 behavior for non-MCP routes remains intact.
<!-- AC:END -->
