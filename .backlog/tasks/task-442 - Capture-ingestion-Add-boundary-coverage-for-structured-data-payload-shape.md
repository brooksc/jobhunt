---
id: TASK-442
title: 'Capture ingestion: Add boundary coverage for structured data payload shape'
status: To Do
assignee: []
created_date: '2026-06-13 18:53'
labels:
  - audit
  - ingestion
  - extension
  - server
dependencies: []
references:
  - core/Services/JobService.swift
  - server/swift/JobhuntServer.swift
  - extension/capture.js
  - tests/CoreTests/CleaningTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Cleaning tests cover structured data when passed directly as `[[String: Any]]`, but the real capture path passes through extension/server fields and `JobService.ingestCapture` only parses `structuredDataJSON`. The extension has been observed sending `structured_data`, so structured data can be dropped while lower-level cleaning tests still pass.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 There is an end-to-end or boundary-level test that sends a capture payload using the actual server/extension field shape and verifies structured job data reaches `Capture.structuredDataJSON` and `cleanedDescription`.
- [ ] #2 The accepted structured-data request field shape is documented or centralized so extension, MCP, server, and ingestion do not drift.
- [ ] #3 Malformed structured-data payloads fail safely or degrade clearly without losing visible/selected text ingestion.
- [ ] #4 Existing cleaning unit tests remain focused on pure cleaning behavior.
<!-- AC:END -->
