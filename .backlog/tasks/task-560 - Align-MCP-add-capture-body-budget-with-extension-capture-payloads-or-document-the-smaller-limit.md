---
id: TASK-560
title: >-
  Align MCP add-capture body budget with extension capture payloads or document
  the smaller limit
status: To Do
assignee: []
created_date: '2026-06-20 00:16'
labels:
  - audit
  - capture-ingestion
  - mcp
  - api-limits
dependencies: []
references:
  - 'server/swift/JobhuntServer.swift:302'
  - 'server/swift/JobhuntServer.swift:309'
  - 'mcp/swift/MCPHelpers.swift:143'
  - 'server/swift/MCPBridgeRoutes.swift:725'
modified_files:
  - server/swift/JobhuntServer.swift
  - server/swift/MCPBridgeRoutes.swift
  - mcp/swift/MCPHelpers.swift
  - tests/ServerTests/JobhuntServerTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: the local server gives `/captures` a 4 MB request budget because captures carry full visible page text (`server/swift/JobhuntServer.swift:302`). All `/mcp/` routes share a 1 MB budget (`server/swift/JobhuntServer.swift:309`), including `/mcp/captures/add`, even though the MCP tool is also described as creating a capture from browser content and accepts `visible_text`/`selected_text` (`mcp/swift/MCPHelpers.swift:143`, `server/swift/MCPBridgeRoutes.swift:725`).

Why important: a full-page capture that succeeds through the Chrome extension can fail with 413 through MCP solely because it used a different external surface. That is hard to diagnose because the semantic operation is the same: add a capture. It also pressures MCP clients to truncate content differently than the extension, which can reduce extraction quality and duplicate detection consistency.

Suggested implementation: make `maxBodySize(forPath:)` route-specific enough to give `/mcp/captures/add` the same budget as `/captures`, or explicitly document and test that MCP capture is intentionally smaller. Prefer route-specific alignment for capture semantics while keeping smaller limits for other MCP metadata/read routes. Add a server test that an over-1MB but under-4MB MCP add-capture request is accepted or, if intentionally rejected, that the error/help text makes the distinction clear.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `/mcp/captures/add` has an intentional, tested body-size budget rather than inheriting the generic MCP limit accidentally.
- [ ] #2 If MCP add-capture is meant to support full browser captures, requests between 1 MB and 4 MB are accepted like `/captures`.
- [ ] #3 If the smaller MCP limit remains, the MCP tool description and failure behavior clearly communicate that clients must send smaller/truncated capture content.
<!-- AC:END -->
