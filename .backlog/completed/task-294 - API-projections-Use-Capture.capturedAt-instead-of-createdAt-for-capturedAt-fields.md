---
id: TASK-294
title: >-
  API projections: Use Capture.capturedAt instead of createdAt for capturedAt
  fields
status: Done
assignee: []
created_date: '2026-06-12 04:39'
updated_date: '2026-06-12 05:47'
labels:
  - audit
  - api
  - mcp
  - reporting
  - dates
dependencies: []
references:
  - core/Models/Projections.swift
  - core/Models/Capture.swift
  - tests/ServerTests/JobhuntServerTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
JobListRecord and JobDetailRecord expose capturedAt using job.capture?.createdAt even though Capture has a distinct capturedAt timestamp. Return actual capture time with appropriate fallback.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 JobListRecord.capturedAt and JobDetailRecord.capturedAt use Capture.capturedAt when available.
- [ ] #2 Fallback behavior for legacy rows without capture data is documented and tested.
- [ ] #3 Server/MCP tests cover captures where capturedAt and createdAt differ.
<!-- AC:END -->
