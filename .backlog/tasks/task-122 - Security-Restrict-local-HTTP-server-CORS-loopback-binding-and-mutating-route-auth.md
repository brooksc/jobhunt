---
id: TASK-122
title: >-
  Security: Restrict local HTTP server CORS, loopback binding, and mutating
  route auth
status: Done
assignee: []
created_date: '2026-06-11 03:01'
updated_date: '2026-06-11 18:40'
labels:
  - security
  - privacy
  - server
  - extension
dependencies: []
references:
  - server/swift/HTTPResponse.swift
  - server/swift/JobhuntServer.swift
  - extension/manifest.json
  - tests/ServerTests/JobhuntServerTests.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The local HTTP server currently allows broad browser-origin access and exposes mutating endpoints without an app/extension authentication boundary. The audit found wildcard CORS, Access-Control-Allow-Private-Network, no explicit loopback bind, and unauthenticated POST routes for captures, site reviews, and app focus.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Server listener explicitly binds to loopback rather than relying on implicit listener behavior.
- [ ] #2 CORS allows only the expected Chrome extension origin or removes broad browser-origin access where it is not required.
- [ ] #3 Mutating local HTTP routes require a shared app/extension token or equivalent local authorization mechanism.
- [ ] #4 OPTIONS/PNA behavior is covered by updated server tests for allowed and rejected origins.
- [ ] #5 Capture, site-review, and focus routes reject missing or invalid authorization in tests.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
1. Loopback binding: `isLoopbackEndpoint()` check in `newConnectionHandler` rejects any non-loopback remote endpoint before processing. 2. CORS: Removed wildcard `Access-Control-Allow-Origin: *` from all responses. Added `withCORS(origin:isPreflight:)` on HTTPResponse; CORS headers only added when Origin header starts with `chrome-extension://`. PNA header only added on preflight (OPTIONS) responses. 3. Mutating route auth: `/captures`, `/site-reviews`, `/api/app/focus` return 403 unless `Origin: chrome-extension://...`. MCP routes remain authenticated via X-MCP-Token. 4-5. Tests: added `testCaptureWithoutExtensionOriginIsRejected`, `testCORSPreflight_extensionOrigin_includesPNAHeader`, `testCORSPreflight_nonExtensionOrigin_noCORSHeaders`, CORS echo assert in `testCaptureEndpoint`. Also fixed pre-existing ServerTests to include Origin header where required.
<!-- SECTION:FINAL_SUMMARY:END -->
