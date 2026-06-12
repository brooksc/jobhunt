---
id: TASK-205
title: 'Server: Expand route boundary tests for extension and MCP APIs'
status: To Do
assignee: []
created_date: '2026-06-12 00:17'
labels:
  - server
  - tests
  - api
  - extension
  - mcp
  - audit
dependencies: []
references:
  - Tests/ServerTests/JobhuntServerTests.swift
  - server/swift/JobhuntServer.swift
  - server/swift/HTTPRequest.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Server tests cover core happy paths and some CORS/MCP auth regressions, but several boundary contracts are not covered: site reviews, jobs-by-url, app focus, parser behavior with non-ASCII bodies, oversize bodies, invalid methods, and MCP limit bounds.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Server tests cover /site-reviews, /api/jobs/by-url, and /api/app/focus behavior.
- [ ] #2 Parser tests cover non-ASCII JSON, malformed requests, invalid methods, and oversize bodies.
- [ ] #3 MCP tests cover list limit bounds and route error semantics.
<!-- AC:END -->
