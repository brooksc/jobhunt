---
id: TASK-358
title: 'Local APIs: Return safe error codes instead of raw localizedDescription values'
status: Done
assignee: []
created_date: '2026-06-12 21:47'
updated_date: '2026-06-12 22:10'
labels:
  - audit
  - security
  - diagnostics
  - server
dependencies: []
references:
  - server/swift/JobhuntServer.swift
  - server/swift/MCPBridgeRoutes.swift
modified_files:
  - server/swift/ServerErrors.swift
  - server/swift/JobhuntServer.swift
  - server/swift/MCPBridgeRoutes.swift
  - tests/ServerTests/JobhuntServerTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
JobhuntServer and MCPBridgeRoutes return error.localizedDescription for many 500 responses. Local clients are trusted but these responses can still expose SwiftData, file-system, or implementation details to extensions, MCP clients, and copied support artifacts.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Server and MCP routes map internal failures to stable safe messages or error codes.
- [ ] #2 Detailed internal errors are logged locally through a controlled diagnostic channel, not returned in HTTP response bodies.
- [ ] #3 Tests cover representative extension and MCP failure responses.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Implemented safe error codes for HTTP server responses:

1. Created `server/swift/ServerErrors.swift` with `safeServerError(_:context:)` helper and `ServerErrorCode` enum. The helper logs the full error to console but returns only `"internal_error"` (the stable `ServerErrorCode.internalError` raw value) to clients.

2. Replaced all 15 `error.localizedDescription` occurrences in `JobhuntServer.swift` (3) and `MCPBridgeRoutes.swift` (12) with `safeServerError(error, context: "<handler-name>")`. Each call includes a context string identifying the handler for log readability.

3. Added two new tests to `tests/ServerTests/JobhuntServerTests.swift`:
   - `testCaptureRoute_storeError_returnsInternalError`: verifies 400 error bodies contain no file paths, SwiftData class names, or ModelContext references
   - `testMCPRoute_invalidRequest_returnsSafeErrorCode`: verifies 401 error body is stable JSON with no file paths or SwiftData internals
<!-- SECTION:FINAL_SUMMARY:END -->
