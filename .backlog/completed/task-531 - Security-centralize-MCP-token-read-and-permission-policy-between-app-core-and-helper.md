---
id: TASK-531
title: >-
  Security: centralize MCP token read and permission policy between app core and
  helper
status: Done
assignee: []
created_date: '2026-06-19 04:51'
updated_date: '2026-06-26 01:40'
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
- [x] #1 The MCP helper no longer duplicates the token path or permission-bit policy from `MCPTokenManager`.
- [x] #2 Both app and helper use one shared implementation for reading a token and rejecting broad file permissions.
- [x] #3 Tests cover successful owner-only token reads and rejection of group/world-readable token files through the helper-facing API.
- [x] #4 Existing behavior for missing token files remains unchanged: helper startup fails closed with a clear error.
- [x] #5 No production token path is touched by tests.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
MCPHelpers.readToken now delegates to MCPTokenManager.read(at:) — one shared token path + owner-only (0o077) permission policy. Removed the duplicated stat/permission logic, which had drifted (helper rejected owner-execute via 0o177, core used 0o077). Made the MCPTokenManager URL seams public so the JobhuntMCP target reuses them. readToken(at: = tokenURL) keeps production callers unchanged and still fails closed on a missing token. MCPTests exercise owner-only read, group/world-readable rejection, and missing-file through readToken's seam — none touch the real ~/.jobhunt-mcp-token. Commit: see git log (lint clean, MCPTests 21 + token tests 6 pass).
<!-- SECTION:FINAL_SUMMARY:END -->
