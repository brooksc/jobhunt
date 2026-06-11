---
id: TASK-122
title: >-
  Security: Restrict local HTTP server CORS, loopback binding, and mutating
  route auth
status: To Do
assignee: []
created_date: '2026-06-11 03:01'
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
