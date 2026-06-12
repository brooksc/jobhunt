---
id: TASK-263
title: >-
  Integration: Make MCP `update_job` persist advertised salary fields or remove
  them from schema
status: To Do
assignee: []
created_date: '2026-06-12 02:56'
labels:
  - audit
  - integration
  - mcp
  - data-integrity
dependencies: []
references:
  - mcp/swift/MCPHelpers.swift
  - server/swift/MCPBridgeRoutes.swift
  - core/Services/JobService.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The MCP tool schema advertises `salary_min`, `salary_max`, and `salary_note`, and the server decodes those fields, but `handleMCPJobUpdate` only applies company, title, and location. Agents can receive a success response for salary updates that are silently ignored.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 MCP `update_job` either persists salary fields correctly or no longer advertises them in the tool schema.
- [ ] #2 Server tests verify each advertised update field is persisted or rejected explicitly.
- [ ] #3 MCP error/success responses do not report success for ignored fields.
<!-- AC:END -->
