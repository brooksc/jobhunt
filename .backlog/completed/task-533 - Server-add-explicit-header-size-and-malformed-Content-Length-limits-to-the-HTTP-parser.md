---
id: TASK-533
title: >-
  Server: add explicit header-size and malformed Content-Length limits to the
  HTTP parser
status: Done
assignee: []
created_date: '2026-06-19 04:51'
updated_date: '2026-06-26 01:46'
labels:
  - audit
  - security
  - server
  - http
  - parser
dependencies: []
references:
  - server/swift/JobhuntServer.swift
  - server/swift/HTTPRequest.swift
  - tests/ServerTests/JobhuntServerTests.swift
  - tests/ServerTests/ServerTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: the server has route-level body limits, but request header accumulation is bounded only by the generic `buffer.count < 2 * 1_048_576` guard while waiting for a parseable request. `peekRequestHeaders` treats malformed or missing `Content-Length` as zero, and `parseHTTPRequest` treats malformed/non-positive `Content-Length` as no body. There are no focused tests for oversized headers, malformed content length, duplicate content length, or body-bearing POSTs without valid length.

Why this matters: this is a localhost server, but any local process can connect. Parser resource and framing rules should fail closed before application routing. A small explicit header cap and strict content-length validation make the parser easier to reason about and reduce risk from slow/malformed local clients.

Suggested implementation: define a modest max header size, reject headers that exceed it before accumulating up to the body cap, and make content-length parsing explicit: reject malformed, negative, duplicate/conflicting values, and POST/PUT-style bodies without a valid length unless the route is known to be bodyless. Add unit tests around `parseHTTPRequest`/`peekRequestHeaders` plus server-level tests where feasible.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Requests whose header block exceeds the configured header limit are rejected with a clear 400/431-style response before body routing.
- [x] #2 Malformed, negative, or conflicting duplicate `Content-Length` headers are rejected instead of being interpreted as an empty body.
- [x] #3 Body-bearing POST routes without a valid `Content-Length` fail with an explicit framing error.
- [x] #4 Existing valid requests with UTF-8 JSON bodies and normal Content-Length continue to parse correctly.
- [x] #5 Focused parser tests cover oversized headers, malformed length, duplicate/conflicting length, missing length on POST, and valid multi-byte JSON body framing.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Replaced peekRequestHeaders with inspectRequestFraming(_:maxHeaderBytes:), called from the receive loop before routing. Enforces a 64 KB header-block cap (→431, whether or not the terminator has arrived), strict Content-Length (non-negative integer; malformed/negative →400), conflicting-duplicate Content-Length rejection (→400), and missing Content-Length on POST/PUT/PATCH (→400 instead of being treated as an empty body). The over-limit 413 check and incremental body accumulation (parse returns nil until the body fully arrives) are preserved, so valid requests — including multi-byte UTF-8 JSON framed by byte count — are unchanged. New RequestFramingTests cover oversized headers, malformed/negative/conflicting length, missing length on POST, and valid multi-byte framing; full ServerTests suite (40, incl. the 413 and all POST routes) passes. Lint clean.
<!-- SECTION:FINAL_SUMMARY:END -->
