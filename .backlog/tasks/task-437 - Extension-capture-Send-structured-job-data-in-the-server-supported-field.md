---
id: TASK-437
title: 'Extension capture: Send structured job data in the server-supported field'
status: Done
assignee: []
created_date: '2026-06-13 18:25'
updated_date: '2026-06-16 23:24'
labels:
  - audit
  - extension
  - capture
  - ingestion
dependencies: []
references:
  - extension/capture.js
  - server/swift/JobhuntServer.swift
  - core/Services/JobService.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`capture.js` builds a `structured_data` array containing JSON-LD and Greenhouse-enriched job data, but the Swift server decodes only `structured_data_json`. As a result, structured data can be silently dropped before ingestion, weakening downstream parsing and extraction.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Captured structured data is sent using a field shape the Swift server decodes and stores.
- [x] #2 Greenhouse-enriched structured data reaches the ingestion layer and is available to downstream parsing/extraction.
- [x] #3 Existing visible/selected text capture behavior is preserved.
- [x] #4 Add extension and/or server tests covering a payload with structured job data.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
`capture.js` now sends `structured_data_json` (the server's preferred typed field — the stringified structured_data array, including Greenhouse-enriched JSON-LD pushed in by `fetchGreenhouseJobData`) in addition to the existing `structured_data` array (kept for preflight stats + as a fallback). The server's `CaptureRequestParsing.resolveStructuredDataJSON` (TASK-442) prefers the typed field, so structured data now reaches ingestion via the explicit contract rather than only the raw-body fallback (AC#1/#2). Visible/selected text capture is unchanged (AC#3). AC#4: new ServerTests E2E accepts the dual-field shape; the TASK-442 resolver test (`testResolveStructuredData_prefersTypedField`) covers typed-wins precedence for exactly this payload, and the JobService boundary test confirms `structured_data_json` reaches `Capture.structuredDataJSON` + `cleanedDescription`. Note: I can't build/run the Chrome extension in this environment, so the JS change is verified by review + the server-side tests for the resulting payload shape.
<!-- SECTION:FINAL_SUMMARY:END -->
