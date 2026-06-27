---
id: TASK-534
title: 'Server: include status text for every emitted HTTP status code'
status: Done
assignee: []
created_date: '2026-06-19 04:53'
updated_date: '2026-06-27 22:06'
labels:
  - audit
  - server
  - http
  - diagnostics
dependencies: []
references:
  - server/swift/HTTPResponse.swift
  - server/swift/MCPBridgeRoutes.swift
  - tests/ServerTests/JobhuntServerTests.swift
modified_files:
  - server/swift/HTTPResponse.swift
  - tests/ServerTests/ServerTests.swift
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: `HTTPResponse.toHTTPBytes()` builds the HTTP status line from a local `statusText(for:)` switch, but the switch does not cover every status code the server emits. For example, MCP method rejection emits 405 while `statusText(for:)` falls through to `Unknown`, producing a status line such as `HTTP/1.1 405 Unknown`.

Why this matters: most clients key off the numeric status code, so this is low severity, but incorrect reason phrases make raw HTTP diagnostics misleading and can hide future additions such as parser-level 431 responses. This helper is a single protocol boundary; it should either know all emitted codes or fail in a way tests catch.

Suggested implementation: add mappings for currently emitted missing statuses, starting with `405 Method Not Allowed`, and include any new parser/status codes introduced by related work such as oversized-header handling. Add focused tests against serialized response bytes so future emitted statuses do not silently degrade to `Unknown`. Consider replacing the open-ended `Int` API with a small status enum if the status surface continues to grow.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `HTTPResponse.statusText(for:)` covers every status code currently emitted by the server, including 405.
- [x] #2 Any new HTTP parser limits added by related work also get matching status text coverage, such as 431 if used.
- [x] #3 Serialized response tests assert representative status lines include the expected reason phrase rather than `Unknown`.
- [x] #4 Existing response bodies and headers remain unchanged except for the reason phrase.
- [x] #5 The implementation stays local to the HTTP response boundary unless a broader status enum is justified by surrounding changes.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added the two missing reason phrases to `HTTPResponse.statusText(for:)`: 405 → "Method Not Allowed" (emitted by MCP method rejection) and 431 → "Request Header Fields Too Large" (emitted by inspectRequestFraming for oversized headers). Made `statusText` internal (was private) so it can be tested directly.

AC#1/#2: `testStatusText_coversEveryEmittedCode` iterates every code the server emits (200/201/204/400/401/403/404/405/413/431/500/503) and asserts none returns "Unknown". AC#3: `testSerializedStatusLine_includesReasonPhrase` asserts the actual serialized bytes read "HTTP/1.1 405 Method Not Allowed". AC#4: only the reason phrase changed — bodies/headers/codes untouched. AC#5: kept the change local to the HTTPResponse boundary (a switch addition); no status enum introduced. All 52 ServerTests green.
<!-- SECTION:FINAL_SUMMARY:END -->
