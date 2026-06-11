---
id: TASK-151
title: 'Privacy: Make MCP raw captured text exposure explicit and controllable'
status: To Do
assignee: []
created_date: '2026-06-11 04:35'
labels:
  - privacy
  - mcp
  - server
dependencies: []
references:
  - server/swift/MCPBridgeRoutes.swift
  - core/Models/Projections.swift
  - mcp/swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Security/privacy audit finding: MCP job detail responses include full `selected_text` and `visible_text` from captured pages. This may be intentional for local agent workflows, but it should be explicit and ideally gated separately from structured job metadata.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 MCP documentation states that job detail can expose raw captured page text to MCP clients with the token.
- [ ] #2 The MCP job detail API either defaults to structured fields only with an explicit raw-text option, or the product decision to include raw text by default is documented.
- [ ] #3 Tests cover the default/raw-text response shape so sensitive fields are not accidentally exposed by future projection changes.
- [ ] #4 If raw text remains available, UI or setup copy communicates the trust boundary for local MCP clients.
<!-- AC:END -->
