---
id: TASK-390
title: >-
  HTTP server: Return serialization failures as server errors instead of 200
  empty JSON
status: To Do
assignee: []
created_date: '2026-06-12 22:58'
labels:
  - audit
  - error-handling
  - server
dependencies: []
references:
  - server/swift/HTTPResponse.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
HTTPResponse.ok currently catches JSON encoding failure and returns `{}` with HTTP 200. If a response payload becomes non-encodable or encoding changes fail, clients see a successful empty body instead of a server error. Make response serialization failures explicit.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Successful responses cannot silently degrade to `{}` on encoding failure.
- [ ] #2 Serialization failures return an explicit 5xx response or throw to the caller for centralized handling.
- [ ] #3 Tests cover encoding failure behavior for success and error response helpers.
<!-- AC:END -->
