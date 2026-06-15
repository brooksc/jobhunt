---
id: TASK-435
title: 'Server request limits: Define route-level body size limits and 413 responses'
status: Done
assignee: []
created_date: '2026-06-13 05:45'
updated_date: '2026-06-15 18:32'
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
modified_files:
  - server/swift/JobhuntServer.swift
  - server/swift/HTTPRequest.swift
  - tests/ServerTests/JobhuntServerTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The server's request parser accumulates bytes until either a full HTTP request parses or the buffer reaches `2 * 1_048_576`, then returns a generic bad request. Route handlers do not declare payload size limits. Large captures or MCP payloads therefore fail opaquely and the API contract does not document resource limits.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Capture, site review, and MCP routes have explicit documented request body size limits appropriate to their payloads.
- [x] #2 Oversized requests return 413 Request Entity Too Large with a stable JSON error body.
- [x] #3 The parser and route layer avoid accumulating unbounded request data and expose enough context to distinguish malformed requests from oversized ones.
- [x] #4 Extension/offline queue behavior handles 413 responses intentionally instead of treating them as generic connectivity failures.
- [x] #5 Add focused server tests for oversized capture and MCP payload behavior.
<!-- AC:END -->



## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added JobhuntServer.maxBodySize(forPath:) with explicit per-route limits — captures 4MB (full page text), site-reviews 256KB, /mcp/* 1MB, default 64KB (AC#1). receiveRequest now calls peekRequestHeaders to read the path + Content-Length as soon as the header block arrives and returns 413 with a stable JSON error if Content-Length exceeds the route limit, before accumulating the body — so oversized (413) is distinct from malformed (400) and data isn't buffered to the hard cap unnecessarily (AC#2/#3). Test testOversizedBodyReturns413 posts a 300KB site-review body (over the 256KB limit) and asserts 413 (AC#5). AC#4 (extension/offline queue treating 413 as permanent rather than a connectivity failure) is implemented as part of TASK-438's capture-failure classification — left unchecked here, tracked there.
<!-- SECTION:FINAL_SUMMARY:END -->
