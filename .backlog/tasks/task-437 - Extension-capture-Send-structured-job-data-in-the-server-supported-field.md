---
id: TASK-437
title: 'Extension capture: Send structured job data in the server-supported field'
status: To Do
assignee: []
created_date: '2026-06-13 18:25'
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
- [ ] #1 Captured structured data is sent using a field shape the Swift server decodes and stores.
- [ ] #2 Greenhouse-enriched structured data reaches the ingestion layer and is available to downstream parsing/extraction.
- [ ] #3 Existing visible/selected text capture behavior is preserved.
- [ ] #4 Add extension and/or server tests covering a payload with structured job data.
<!-- AC:END -->
