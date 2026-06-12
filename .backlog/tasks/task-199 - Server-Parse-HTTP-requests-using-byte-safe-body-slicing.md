---
id: TASK-199
title: 'Server: Parse HTTP requests using byte-safe body slicing'
status: Done
assignee: []
created_date: '2026-06-12 00:16'
updated_date: '2026-06-12 02:08'
labels:
  - server
  - api
  - http
  - reliability
  - audit
dependencies: []
references:
  - server/swift/HTTPRequest.swift
  - server/swift/JobhuntServer.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The hand-rolled HTTP parser converts the entire request to a UTF-8 String, then slices the body using Content-Length. Content-Length is byte-based, so non-ASCII JSON bodies can be truncated or misread.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 HTTP headers are parsed separately from the original Data body without converting the entire request to String.
- [ ] #2 Content-Length is applied as a byte count against Data, not String characters.
- [ ] #3 Server tests cover non-ASCII JSON request bodies.
<!-- AC:END -->
