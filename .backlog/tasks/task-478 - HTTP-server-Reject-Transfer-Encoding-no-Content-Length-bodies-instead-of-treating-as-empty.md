---
id: TASK-478
title: >-
  HTTP server: Reject Transfer-Encoding/no-Content-Length bodies instead of
  treating as empty
status: To Do
assignee: []
created_date: '2026-06-15 03:40'
labels:
  - bug
  - server
dependencies: []
references:
  - server/swift/HTTPRequest.swift
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`parseHTTPRequest` (HTTPRequest.swift:67-77) only reads a body when a numeric Content-Length header is present. A request using `Transfer-Encoding: chunked` (or any body without Content-Length) parses successfully the moment headers arrive with body == nil; POST handlers then return "Invalid JSON body" / "url required" instead of processing the payload, and the chunk framing bytes are discarded. Masked in practice because the extension and MCP bridge (URLSession) always set Content-Length. Fix: reject requests carrying Transfer-Encoding with 400 (explicitly unsupported), or implement chunked de-framing.
<!-- SECTION:DESCRIPTION:END -->
