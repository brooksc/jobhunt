---
id: TASK-435
title: 'Server request limits: Define route-level body size limits and 413 responses'
status: To Do
assignee: []
created_date: '2026-06-13 05:45'
labels:
  - audit
  - server
  - extension
  - mcp
dependencies: []
references:
  - server/swift/JobhuntServer.swift
  - server/swift/HTTPRequest.swift
  - server/swift/HTTPResponse.swift
  - extension/service_worker.js
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The server's request parser accumulates bytes until either a full HTTP request parses or the buffer reaches `2 * 1_048_576`, then returns a generic bad request. Route handlers do not declare payload size limits. Large captures or MCP payloads therefore fail opaquely and the API contract does not document resource limits.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Capture, site review, and MCP routes have explicit documented request body size limits appropriate to their payloads.
- [ ] #2 Oversized requests return 413 Request Entity Too Large with a stable JSON error body.
- [ ] #3 The parser and route layer avoid accumulating unbounded request data and expose enough context to distinguish malformed requests from oversized ones.
- [ ] #4 Extension/offline queue behavior handles 413 responses intentionally instead of treating them as generic connectivity failures.
- [ ] #5 Add focused server tests for oversized capture and MCP payload behavior.
<!-- AC:END -->
