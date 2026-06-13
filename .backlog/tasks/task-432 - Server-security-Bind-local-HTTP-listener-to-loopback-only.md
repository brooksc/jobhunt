---
id: TASK-432
title: 'Server security: Bind local HTTP listener to loopback only'
status: To Do
assignee: []
created_date: '2026-06-13 05:43'
labels:
  - audit
  - server
  - security
dependencies: []
references:
  - server/swift/JobhuntServer.swift
  - extension/service_worker.js
  - mcp/swift/MCPHelpers.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`JobhuntServer.startListener` constructs a plain TCP `NWListener` for candidate ports without a visible loopback-only binding or remote-address rejection. The product and privacy model describe a localhost-only companion server, so the server should enforce loopback at the networking boundary rather than relying on client behavior or route-level headers.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The local HTTP server accepts connections only from loopback addresses/interfaces.
- [ ] #2 Non-loopback connections are rejected before route handling or cannot connect because the listener is bound to loopback.
- [ ] #3 Tests or a documented verification path prove the server is not reachable from non-loopback interfaces.
- [ ] #4 Extension and MCP helper clients continue to connect through `127.0.0.1`.
- [ ] #5 Server/privacy documentation accurately states the enforced binding behavior.
<!-- AC:END -->
