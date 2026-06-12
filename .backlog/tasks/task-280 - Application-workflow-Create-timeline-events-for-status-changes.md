---
id: TASK-280
title: 'Application workflow: Create timeline events for status changes'
status: Done
assignee: []
created_date: '2026-06-12 03:36'
updated_date: '2026-06-12 03:58'
labels:
  - audit
  - application-workflow
  - timeline
  - status
dependencies: []
references:
  - core/Services/JobService.swift
  - core/Models/JobEvent.swift
  - app/Views/Detail/JobDetailView.swift
modified_files:
  - core/Services/JobService.swift
  - tests/CoreTests/JobServiceTests.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
setStatus and setStatusBulk update the job status without writing JobEvent records, even though the timeline UI supports applied/interview/offer/rejected/status-change events. Record status transitions so application history is auditable.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Single status changes create timeline events with old and new status context.
- [x] #2 Bulk status changes create appropriate events without excessive duplicate writes.
- [x] #3 Tests cover status changes creating visible timeline/history records.
<!-- AC:END -->
