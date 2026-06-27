---
id: TASK-560
title: >-
  Align MCP add-capture body budget with extension capture payloads or document
  the smaller limit
status: Done
assignee: []
created_date: '2026-06-20 00:16'
updated_date: '2026-06-27 21:57'
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
- [x] #1 `/mcp/captures/add` has an intentional, tested body-size budget rather than inheriting the generic MCP limit accidentally.
- [x] #2 If MCP add-capture is meant to support full browser captures, requests between 1 MB and 4 MB are accepted like `/captures`.
- [x] #3 If the smaller MCP limit remains, the MCP tool description and failure behavior clearly communicate that clients must send smaller/truncated capture content.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Aligned the MCP add-capture body budget with /captures (chose alignment over documenting a smaller limit, since both are the same "add a capture from browser content" operation).

- `maxBodySize(forPath:)` now returns the 4 MB capture budget for both `/captures` and `/mcp/captures/add` (listed before the generic `/mcp/` case so it isn't accidentally capped at 1 MB); other MCP routes keep 1 MB.
- Fixed a latent limiter that undermined this: the request-accumulation loop (`readMoreOrFail`) capped total bytes at 2 MB, rejecting in-budget bodies of 2–4 MB with a 400 before they finished arriving — which silently capped even `/captures` at 2 MB despite its 4 MB budget. Introduced `maxRequestBytes = 4 MB + maxHeaderBytes` as the accumulation ceiling.

AC#1: `testMaxBodySize_captureRoutesShareLargeBudget` pins the intentional per-route budgets (capture routes 4 MB, other MCP 1 MB). AC#2: `testMCPCaptureAdd_acceptsBodyOver1MB` sends a ~2.1 MB capture through /mcp/captures/add and asserts 200 (it returned 400 before the accumulation-cap fix). AC#3: n/a — the limit was aligned, not kept smaller. All 47 ServerTests green.

Note surfaced to user: the 2 MB accumulation cap was a pre-existing bug affecting /captures too; this fix lets /captures genuinely accept up to its 4 MB budget.
<!-- SECTION:FINAL_SUMMARY:END -->
