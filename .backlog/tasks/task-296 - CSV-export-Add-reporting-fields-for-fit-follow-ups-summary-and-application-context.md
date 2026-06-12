---
id: TASK-296
title: >-
  CSV export: Add reporting fields for fit, follow-ups, summary, and application
  context
status: To Do
assignee: []
created_date: '2026-06-12 04:39'
labels:
  - audit
  - export
  - reporting
  - data-portability
dependencies: []
references:
  - core/Services/ExportService.swift
  - tests/CoreTests/JobServiceTests.swift
  - core/Models/Job.swift
  - core/Models/Projections.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CSV export currently emits a narrow 19-column job list and omits fit score/status, follow-up state, application instructions, extracted summary/skills, and other fields now used in dashboard/detail views. Expand export or provide a richer reporting export.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 CSV export includes fit score/status and key workflow/reporting fields, or a separate richer export is added.
- [ ] #2 Application URL/source URL semantics are documented in exported columns.
- [ ] #3 Tests assert the expanded column set and representative values.
<!-- AC:END -->
