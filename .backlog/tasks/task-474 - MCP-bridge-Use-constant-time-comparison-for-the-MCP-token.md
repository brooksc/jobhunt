---
id: TASK-474
title: 'MCP bridge: Use constant-time comparison for the MCP token'
status: To Do
assignee: []
created_date: '2026-06-15 03:39'
labels:
  - security
  - server
  - mcp
dependencies: []
references:
  - server/swift/MCPBridgeRoutes.swift
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`provided == mcpToken` (MCPBridgeRoutes.swift:233) short-circuits on the first differing byte, leaking token length/prefix via timing. The attack surface is limited (loopback-only, and any local process can already read ~/.jobhunt-mcp-token), so this is low priority, but a constant-time compare is cheap and matches the fail-closed intent already coded around it. Fix: compare with a constant-time routine (XOR-accumulate over equal-length byte buffers, or compare SHA-256 digests).
<!-- SECTION:DESCRIPTION:END -->
