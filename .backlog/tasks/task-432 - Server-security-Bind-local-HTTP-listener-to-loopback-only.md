---
id: TASK-432
title: 'Server security: Bind local HTTP listener to loopback only'
status: In Progress
assignee:
  - claude
created_date: '2026-06-13 05:43'
updated_date: '2026-06-15 00:27'
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

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Bind the local NWListener to loopback only.

- In `JobhuntServer.startListener`, set `params.requiredInterfaceType = .loopback` on the `NWParameters.tcp` before constructing `NWListener`. This makes the OS bind the listener to the loopback interface; non-loopback peers cannot connect (AC #1/#2 via the "cannot connect" branch).
- 127.0.0.1 clients (Chrome extension, MCP helper) are unaffected (AC #4) — existing ServerTests connect via 127.0.0.1 and continue to pass.
- AC #3: loopback binding is OS-enforced; document the verification path (e.g. `nc <LAN-IP> <port>` refused) in the code comment; existing 127.0.0.1 tests prove loopback serving works.
- Update the server doc/comment to state the enforced loopback binding (AC #5).
<!-- SECTION:PLAN:END -->
