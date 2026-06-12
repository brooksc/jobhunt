---
id: TASK-262
title: 'Integration: Preserve extension structured data during capture ingestion'
status: Done
assignee: []
created_date: '2026-06-12 02:56'
updated_date: '2026-06-12 03:13'
labels:
  - audit
  - integration
  - extension
  - capture
  - llm
dependencies: []
references:
  - extension/capture.js
  - server/swift/JobhuntServer.swift
  - core/Services/JobService.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The extension emits `structured_data` as an array, including JSON-LD and Greenhouse-enriched posting data, while the Swift server only decodes `structured_data_json`. The normal browser capture path can therefore drop the richest structured source data before extraction.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The capture endpoint accepts the extension-emitted `structured_data` field and stores it as `Capture.structuredDataJSON`, or the extension sends the server-supported `structured_data_json` field.
- [ ] #2 Greenhouse-enriched structured data survives a full extension-to-server capture round trip.
- [ ] #3 Tests cover structured data array payloads, existing `structured_data_json` payloads if retained, and payload size limits.
<!-- AC:END -->
