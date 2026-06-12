---
id: TASK-265
title: 'Integration: Reconcile MCP raw-text tool description with server behavior'
status: Done
assignee: []
created_date: '2026-06-12 02:56'
updated_date: '2026-06-12 03:13'
labels:
  - audit
  - integration
  - mcp
  - documentation
dependencies: []
references:
  - mcp/swift/MCPHelpers.swift
  - server/swift/MCPBridgeRoutes.swift
  - tests/ServerTests/JobhuntServerTests.swift
  - README.md
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The MCP helper describes `job_get` as returning raw captured page text by default, but the helper does not send `include_raw_text`, and the server only includes `selected_text` and `visible_text` when that flag is true. Tests currently assert default omission, so either the description is misleading or the helper should intentionally request raw text.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 MCP tool description, README trust-boundary text, helper arguments, and server behavior agree on whether raw text is included by default.
- [ ] #2 If raw text is opt-in, the tool schema exposes an `include_raw_text` argument and documents the privacy implication.
- [ ] #3 Tests cover default omission and explicit raw-text inclusion, or default inclusion if that is the chosen contract.
<!-- AC:END -->
