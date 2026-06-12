---
id: TASK-299
title: 'Availability: Record audit context when auto-expiring jobs'
status: Done
assignee: []
created_date: '2026-06-12 05:01'
updated_date: '2026-06-12 05:47'
labels:
  - audit
  - availability
  - history
dependencies: []
references:
  - core/Services/AvailabilityChecker.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
AvailabilityChecker.checkJobs mutates job.status to expired and posts a notification, but it does not create a JobEvent or persist the URL/status/reason that caused the change. Later investigation cannot explain why the job changed state.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 When availability checking changes a job status, persist an auditable event or equivalent structured reason.
- [ ] #2 The recorded context includes the checked URL and the availability result that triggered expiry.
- [ ] #3 Tests verify that auto-expiry creates the expected audit record.
<!-- AC:END -->
