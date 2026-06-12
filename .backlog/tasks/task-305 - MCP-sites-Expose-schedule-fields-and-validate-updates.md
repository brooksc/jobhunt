---
id: TASK-305
title: 'MCP sites: Expose schedule fields and validate updates'
status: Done
assignee: []
created_date: '2026-06-12 05:01'
updated_date: '2026-06-12 05:47'
labels:
  - audit
  - mcp
  - sites
dependencies: []
references:
  - core/Models/Projections.swift
  - server/swift/MCPBridgeRoutes.swift
  - mcp/swift/MCPHelpers.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
MCP update_site can change interval_days, but list_sites omits scheduling fields such as lastReviewedAt and nextReviewAt. Invalid state values are silently ignored, and intervalDays is not bounded like the HTTP site-review endpoint.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 MCP list_sites exposes enough schedule fields for clients to understand site review state, including nextReviewAt and lastReviewedAt.
- [ ] #2 MCP update_site rejects invalid state values with a clear error.
- [ ] #3 MCP interval updates enforce documented bounds consistent with other site review entry points.
- [ ] #4 Add server/MCP tests for DTO shape and validation failures.
<!-- AC:END -->
