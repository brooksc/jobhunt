---
id: TASK-358
title: 'Local APIs: Return safe error codes instead of raw localizedDescription values'
status: To Do
assignee: []
created_date: '2026-06-12 21:47'
labels:
  - audit
  - security
  - diagnostics
  - server
dependencies: []
references:
  - server/swift/JobhuntServer.swift
  - server/swift/MCPBridgeRoutes.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
JobhuntServer and MCPBridgeRoutes return error.localizedDescription for many 500 responses. Local clients are trusted but these responses can still expose SwiftData, file-system, or implementation details to extensions, MCP clients, and copied support artifacts.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Server and MCP routes map internal failures to stable safe messages or error codes.
- [ ] #2 Detailed internal errors are logged locally through a controlled diagnostic channel, not returned in HTTP response bodies.
- [ ] #3 Tests cover representative extension and MCP failure responses.
<!-- AC:END -->
