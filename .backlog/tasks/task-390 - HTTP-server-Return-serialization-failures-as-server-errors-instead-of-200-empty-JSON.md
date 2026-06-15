---
id: TASK-390
title: >-
  HTTP server: Return serialization failures as server errors instead of 200
  empty JSON
status: Done
assignee: []
created_date: '2026-06-12 22:58'
updated_date: '2026-06-15 18:11'
labels:
  - audit
  - error-handling
  - server
dependencies: []
references:
  - server/swift/HTTPResponse.swift
modified_files:
  - server/swift/HTTPResponse.swift
  - tests/ServerTests/ServerTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
HTTPResponse.ok currently catches JSON encoding failure and returns `{}` with HTTP 200. If a response payload becomes non-encodable or encoding changes fail, clients see a successful empty body instead of a server error. Make response serialization failures explicit.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Successful responses cannot silently degrade to `{}` on encoding failure.
- [x] #2 Serialization failures return an explicit 5xx response or throw to the caller for centralized handling.
- [x] #3 Tests cover encoding failure behavior for success and error response helpers.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
HTTPResponse.ok no longer falls back to a 200 "{}" on encode failure: it now try-encodes and, on failure, returns .error("Response serialization failed", code: 500) (AC#1/#2). The error helper itself already encodes a trivial ErrorBody. Tests (HTTPResponseSerializationTests) cover a throwing Encodable → 500 (non-empty, not "{}") and a valid value → 200 (AC#3).
<!-- SECTION:FINAL_SUMMARY:END -->
