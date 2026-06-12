---
id: TASK-340
title: 'MAS build: Do not generate MCP token files'
status: To Do
assignee: []
created_date: '2026-06-12 20:35'
labels:
  - audit
  - release
  - mas
  - mcp
  - sandbox
dependencies: []
references:
  - app/Shell/AppServices.swift
  - server/swift/JobhuntServer.swift
  - Project.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
AppServices always calls MCPTokenManager.generateAndWrite(), even for MAS builds where MCP routes and helper bundling are excluded. This creates DMG-only token behavior in the sandboxed App Store build for a feature MAS users cannot use.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 MAS builds do not create or write ~/.jobhunt-mcp-token.
- [ ] #2 DMG builds still create the token and enable MCP routes.
- [ ] #3 Tests or build assertions cover MAS_BUILD behavior for MCP token setup.
<!-- AC:END -->
