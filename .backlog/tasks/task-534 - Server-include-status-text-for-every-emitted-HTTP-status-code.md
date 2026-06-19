---
id: TASK-534
title: 'Server: include status text for every emitted HTTP status code'
status: To Do
assignee: []
created_date: '2026-06-19 04:53'
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
- [ ] #1 `HTTPResponse.statusText(for:)` covers every status code currently emitted by the server, including 405.
- [ ] #2 Any new HTTP parser limits added by related work also get matching status text coverage, such as 431 if used.
- [ ] #3 Serialized response tests assert representative status lines include the expected reason phrase rather than `Unknown`.
- [ ] #4 Existing response bodies and headers remain unchanged except for the reason phrase.
- [ ] #5 The implementation stays local to the HTTP response boundary unless a broader status enum is justified by surrounding changes.
<!-- AC:END -->
