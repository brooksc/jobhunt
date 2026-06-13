---
id: TASK-433
title: 'Server compatibility: Align app, extension, and MCP helper port discovery'
status: To Do
assignee: []
created_date: '2026-06-13 05:44'
labels:
  - audit
  - server
  - extension
  - mcp
dependencies: []
references:
  - server/swift/JobhuntServer.swift
  - extension/service_worker.js
  - mcp/swift/MCPHelpers.swift
  - chromestore/store-listing.md
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The app server tries ports `8765...8784` and then an OS-assigned ephemeral port, while the Chrome extension and MCP helper probe only `8765...8769`. If the app binds to `8770+` or ephemeral, the server is running but companion clients report it missing.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The app server, Chrome extension, MCP helper, docs, and store-listing text share one explicit port discovery contract.
- [ ] #2 Companion clients can find every port the app may intentionally bind for normal production use, or the app no longer binds ports that clients cannot discover.
- [ ] #3 The ephemeral fallback is either removed from production companion-server startup or paired with a discovery mechanism clients can use.
- [ ] #4 Add focused tests or contract checks that would fail if app and client port lists drift again.
<!-- AC:END -->
