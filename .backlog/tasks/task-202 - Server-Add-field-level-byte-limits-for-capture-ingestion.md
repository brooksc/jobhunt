---
id: TASK-202
title: 'Server: Add field-level byte limits for capture ingestion'
status: To Do
assignee: []
created_date: '2026-06-12 00:17'
labels:
  - server
  - capture
  - api
  - storage
  - audit
dependencies: []
references:
  - server/swift/JobhuntServer.swift
  - core/Services/JobService.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The /captures endpoint validates only presence for URL, title, and text. Large visible_text, selected_text, structured_data_json, or user_note fields can flow into storage and extraction with no API-level limits.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Capture ingestion defines documented byte limits for high-volume text fields.
- [ ] #2 Oversized fields return clear 400 responses before persistence or LLM queueing.
- [ ] #3 Tests cover boundary-sized and oversized capture payloads.
<!-- AC:END -->
