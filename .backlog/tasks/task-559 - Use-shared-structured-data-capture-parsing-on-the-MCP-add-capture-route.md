---
id: TASK-559
title: Use shared structured-data capture parsing on the MCP add-capture route
status: To Do
assignee: []
created_date: '2026-06-20 00:16'
labels:
  - audit
  - capture-ingestion
  - mcp
  - structured-data
dependencies: []
references:
  - 'server/swift/CaptureRequestParsing.swift:3'
  - 'server/swift/JobhuntServer.swift:529'
  - 'server/swift/MCPBridgeRoutes.swift:455'
  - 'server/swift/MCPBridgeRoutes.swift:725'
modified_files:
  - server/swift/MCPBridgeRoutes.swift
  - server/swift/CaptureRequestParsing.swift
  - mcp/swift/MCPHelpers.swift
  - tests/ServerTests/JobhuntServerTests.swift
  - tests/MCPTests/MCPTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: `CaptureRequestParsing` documents a centralized policy for both `structured_data_json` and raw `structured_data` arrays so the server, MCP bridge, extension, and ingestion do not drift (`server/swift/CaptureRequestParsing.swift:3`). The extension `/captures` route uses that helper with the raw request body (`server/swift/JobhuntServer.swift:529`). The MCP `/mcp/captures/add` route does not; its request type only decodes `structured_data_json` and passes that directly into `CapturePayload` (`server/swift/MCPBridgeRoutes.swift:455`, `server/swift/MCPBridgeRoutes.swift:725`).

Why important: clients that send the same capture shape as the browser extension, especially a `structured_data` JSON array, get different behavior through MCP: the capture succeeds, but structured job metadata is silently dropped. That undermines extraction quality and creates cross-surface behavior drift despite the existence of a shared parser meant to prevent exactly this.

Suggested implementation: update the MCP add-capture path to call `CaptureRequestParsing.resolveStructuredDataJSON(typed:rawBody:)`, matching `/captures`. Either add `structured_data` to the MCP tool schema as an accepted object/array field or clearly document that MCP clients should use `structured_data_json`; prefer accepting both to keep capture surfaces aligned. Add server/MCP route coverage proving `structured_data` arrays survive through `/mcp/captures/add`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `/mcp/captures/add` accepts `structured_data_json` exactly as it does today.
- [ ] #2 `/mcp/captures/add` also accepts a raw `structured_data` array and forwards it into ingestion as structured JSON.
- [ ] #3 The MCP tool schema or helper documentation reflects every accepted structured-data capture shape.
<!-- AC:END -->
