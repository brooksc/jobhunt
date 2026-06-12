---
id: TASK-335
title: 'MCP helper: Enforce token file permission checks consistently'
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
  - mcp/swift/MCPHelpers.swift
  - README.md
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
MCPTokenManager.read refuses ~/.jobhunt-mcp-token when permissions are broader than owner-only, but the MCP helper's readToken() reads the file without checking permissions. This weakens the documented owner-readable-only token boundary.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The MCP helper refuses to use token files with group/world permissions.
- [ ] #2 Token read logic is shared or kept behaviorally identical between the app and helper.
- [ ] #3 MCP tests cover missing token, valid 0600 token, and overly broad token permissions.
<!-- AC:END -->
