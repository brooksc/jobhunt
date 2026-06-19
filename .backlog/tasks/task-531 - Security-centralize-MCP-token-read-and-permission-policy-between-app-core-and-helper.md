---
id: TASK-531
title: >-
  Security: centralize MCP token read and permission policy between app core and
  helper
status: To Do
assignee: []
created_date: '2026-06-19 04:51'
labels:
  - audit
  - security
  - mcp
  - token
  - duplication
dependencies: []
references:
  - core/Settings/MCPTokenManager.swift
  - mcp/swift/MCPHelpers.swift
  - mcp/swift/main.swift
  - tests/MCPTests/MCPTests.swift
  - tests/CoreTests/SettingsStoreTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: `JobhuntCore.MCPTokenManager.read()` and `mcp/swift/MCPHelpers.readToken()` implement the same token path and permission policy separately. The MCP helper imports `JobhuntCore`, but still duplicates the `~/.jobhunt-mcp-token` path, stat/permission checks, and trimming behavior.

Why this matters: token file permissions are an authentication boundary. Duplicating the policy makes it easy for one side to drift, for example accepting broader permissions, changing the token path in only one place, or testing one implementation while the helper uses another. This is a small but important DRY violation in security-sensitive code.

Suggested implementation: make the MCP helper call `MCPTokenManager.read()` directly, or expose a small shared helper that both app and command-line target use. Remove the duplicate path/permission logic from `MCPHelpers.swift` and add MCPTests that exercise owner-only and broad-permission cases through the actual helper path using a testable token URL seam if needed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The MCP helper no longer duplicates the token path or permission-bit policy from `MCPTokenManager`.
- [ ] #2 Both app and helper use one shared implementation for reading a token and rejecting broad file permissions.
- [ ] #3 Tests cover successful owner-only token reads and rejection of group/world-readable token files through the helper-facing API.
- [ ] #4 Existing behavior for missing token files remains unchanged: helper startup fails closed with a clear error.
- [ ] #5 No production token path is touched by tests.
<!-- AC:END -->
