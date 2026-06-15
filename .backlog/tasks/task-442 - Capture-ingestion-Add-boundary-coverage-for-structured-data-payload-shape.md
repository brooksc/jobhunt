---
id: TASK-442
title: 'Capture ingestion: Add boundary coverage for structured data payload shape'
status: Done
assignee: []
created_date: '2026-06-13 18:53'
updated_date: '2026-06-15 20:08'
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
- [x] #1 There is an end-to-end or boundary-level test that sends a capture payload using the actual server/extension field shape and verifies structured job data reaches `Capture.structuredDataJSON` and `cleanedDescription`.
- [x] #2 The accepted structured-data request field shape is documented or centralized so extension, MCP, server, and ingestion do not drift.
- [x] #3 Malformed structured-data payloads fail safely or degrade clearly without losing visible/selected text ingestion.
- [x] #4 Existing cleaning unit tests remain focused on pure cleaning behavior.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Extracted the structured-data field resolution from JobhuntServer into `CaptureRequestParsing.resolveStructuredDataJSON(typed:rawBody:)` — one documented policy (AC#2) for the accepted shapes: the typed `structured_data_json` string, else the extension's raw `structured_data` array on the body, degrading safely to nil when neither is present or the array isn't a valid JSON container (AC#3 — visible/selected text still ingests). JobhuntServer's /captures handler now calls the helper. Tests: ServerTests unit-cover the resolver (typed-wins, raw-array fallback, empty-typed fallthrough, both-absent→nil, malformed scalar/non-JSON→nil); a JobService boundary test (AC#1) verifies structured data reaches `Capture.structuredDataJSON` and is promoted into `cleanedDescription`; the existing E2E `testCaptureEndpoint_acceptsStructuredDataArray` exercises the real server field shape. CleaningTests remain pure cleaning (AC#4). Fast gate (ServerTests + JobServiceTests) green; app builds. Note: MCP capture-add still accepts only the typed field (its clients send the stringified form); documented in the helper as the shared policy if MCP ever needs the array.
<!-- SECTION:FINAL_SUMMARY:END -->
