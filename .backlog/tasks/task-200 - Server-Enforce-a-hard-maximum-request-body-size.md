---
id: TASK-200
title: 'Server: Enforce a hard maximum request body size'
status: Done
assignee: []
created_date: '2026-06-12 00:16'
updated_date: '2026-06-12 02:08'
labels:
  - server
  - api
  - reliability
  - security
  - audit
dependencies: []
references:
  - server/swift/JobhuntServer.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The local HTTP server accumulates request data until Content-Length is satisfied. Each receive chunk is capped, but the total accumulated request body is not capped, allowing a local client to force large memory growth.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The server enforces a documented maximum request size before or during accumulation.
- [ ] #2 Oversize requests are rejected with a clear 4xx response and the connection is closed.
- [ ] #3 Tests cover oversize request handling without excessive memory use.
<!-- AC:END -->
