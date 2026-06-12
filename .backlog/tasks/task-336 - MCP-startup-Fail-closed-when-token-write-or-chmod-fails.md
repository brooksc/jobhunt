---
id: TASK-336
title: 'MCP startup: Fail closed when token write or chmod fails'
status: To Do
assignee: []
created_date: '2026-06-12 20:26'
labels:
  - audit
  - security
  - mcp
  - token
dependencies: []
references:
  - core/Settings/MCPTokenManager.swift
  - app/Shell/AppServices.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
MCPTokenManager.generateAndWrite logs token write/chmod failures but still returns a generated token. The app can start MCP endpoints with an in-memory token even when the helper cannot read the token or the token file was not hardened.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Token generation reports failure to callers instead of returning a usable token after write or permission hardening fails.
- [ ] #2 MCP endpoints are disabled or app startup surfaces a clear error when token setup fails.
- [ ] #3 Tests cover token write/chmod failure behavior where feasible.
<!-- AC:END -->
