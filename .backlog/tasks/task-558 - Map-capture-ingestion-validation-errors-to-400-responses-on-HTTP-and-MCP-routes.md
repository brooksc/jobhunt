---
id: TASK-558
title: >-
  Map capture ingestion validation errors to 400 responses on HTTP and MCP
  routes
status: Done
assignee: []
created_date: '2026-06-20 00:16'
updated_date: '2026-06-27 21:46'
labels:
  - audit
  - capture-ingestion
  - api
  - mcp
dependencies: []
references:
  - 'core/Services/JobService.swift:49'
  - 'core/Services/JobService.swift:88'
  - 'server/swift/JobhuntServer.swift:508'
  - 'server/swift/JobhuntServer.swift:553'
  - 'server/swift/MCPBridgeRoutes.swift:444'
  - 'server/swift/MCPBridgeRoutes.swift:485'
modified_files:
  - server/swift/ServerErrors.swift
  - server/swift/JobhuntServer.swift
  - server/swift/MCPBridgeRoutes.swift
  - tests/ServerTests/JobhuntServerTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: `JobService.ingestCapture` has typed validation failures for missing/invalid URL, missing page title, and missing text (`core/Services/JobService.swift:49`, `core/Services/JobService.swift:88`). The extension route pre-checks some missing-field cases, but any service-level validation failure, such as an invalid `javascript:`/`ftp:` URL or malformed canonical handling that reaches the service, is caught by `handleCapture` and returned via `safeServerError(..., code: 500)` (`server/swift/JobhuntServer.swift:508`, `server/swift/JobhuntServer.swift:553`). The MCP add-capture route has the same catch-all 500 behavior (`server/swift/MCPBridgeRoutes.swift:444`, `server/swift/MCPBridgeRoutes.swift:485`).

Why important: invalid capture input is a client error, not a server outage. Returning 500 misleads the Chrome extension/MCP clients into retrying or surfacing a generic server failure, pollutes diagnostics, and makes support harder because validation problems look like internal failures. It also weakens the completed centralized URL-validation work by losing the typed error at the route boundary.

Suggested implementation: add a small boundary mapper for `JobServiceError` used by both `handleCapture` and `handleMCPCaptureAdd`. Return 400 with stable non-leaking messages for `.missingURL`, `.invalidURL`, `.missingPageTitle`, and `.missingText`; keep unexpected errors on the existing safe 500 path. Add server tests for invalid URL and missing text through both `/captures` and `/mcp/captures/add`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Invalid capture URLs return HTTP 400, not 500, from both `/captures` and `/mcp/captures/add`.
- [x] #2 Missing capture text returns HTTP 400, not 500, from the MCP add-capture route.
- [x] #3 Unexpected persistence/server failures still return stable safe 500 errors.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added a shared boundary mapper `captureIngestionErrorResponse(_:context:)` in ServerErrors.swift: typed `JobServiceError` validation cases (.missingURL/.invalidURL/.missingPageTitle/.missingText) return HTTP 400 with their stable, non-leaking message; all other errors fall back to the existing safe 500 path (`safeServerError`). Wired both `handleCapture` (/captures) and `handleMCPCaptureAdd` (/mcp/captures/add) through it.

AC#1: invalid URL schemes (javascript:, ftp:) now 400 on both routes (tested). AC#2: missing text on the MCP route — which has no text pre-check — now 400 via the service error (tested). AC#3: the existing testCaptureRoute_storeError_returnsInternalError still passes (store faults aren't JobServiceError → safe 500). All 43 ServerTests green.
<!-- SECTION:FINAL_SUMMARY:END -->
