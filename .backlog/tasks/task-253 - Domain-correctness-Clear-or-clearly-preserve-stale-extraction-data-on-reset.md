---
id: TASK-253
title: 'Domain correctness: Clear or clearly preserve stale extraction data on reset'
status: To Do
assignee: []
created_date: '2026-06-12 02:42'
labels:
  - audit
  - domain
  - llm
  - data-quality
dependencies: []
references:
  - core/Services/JobService.swift
  - core/Models/Job.swift
  - tests/CoreTests/JobServiceTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`JobService.resetExtraction` clears extraction status, error, and timestamp, then enqueues extraction, but leaves extracted fields and `extractedJSON` in place. During pending or failed re-extraction, the UI can continue showing stale company/title/location/fit context as if it were current.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Reset extraction behavior is explicitly defined: either stale extracted payload is cleared, or UI labels it as last-known/stale data.
- [ ] #2 Implementation and tests cover `extractedJSON`, extracted scalar fields, extraction metadata, and queued extraction request behavior.
- [ ] #3 Data Quality and detail views do not present stale extracted data as current after reset.
<!-- AC:END -->
