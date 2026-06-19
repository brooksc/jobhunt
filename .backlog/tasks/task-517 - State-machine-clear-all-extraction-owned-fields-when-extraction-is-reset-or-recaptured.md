---
id: TASK-517
title: >-
  State machine: clear all extraction-owned fields when extraction is reset or
  recaptured
status: To Do
assignee: []
created_date: '2026-06-19 02:00'
labels:
  - audit
  - state-machine
  - data-integrity
  - extraction
dependencies: []
references:
  - core/Services/JobService.swift
  - core/Services/BackgroundStore.swift
  - core/Models/Job.swift
  - tests/CoreTests/JobServiceTests.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: extraction reset clears many extracted fields, but newer extraction-owned values such as hourly salary fields, `applicationURL`, and `meetsCriteria` are not cleared. The recapture path for an existing URL moves extraction back to pending but can also leave old extracted values visible while the new extraction is waiting.

Why this matters: once the job lifecycle says extraction is pending, stale extracted values can look current. That can affect user decisions, filters, data quality checks, and outbound actions such as opening an application URL that belongs to a previous extraction result.

Suggested implementation: centralize the list of extraction-owned fields in one helper used by both explicit extraction reset and same-URL recapture requeue. Clear every field populated from extraction output, including salary hourly range, application URL, criteria match, confidence/model/timestamp/error, and structured extraction JSON. Preserve explicitly manual/user-owned fields only where the product intentionally treats them as overrides.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Explicit extraction reset clears all extraction-owned scalar fields, including hourly salary min/max, application URL, and criteria match.
- [ ] #2 Same-URL recapture that requeues extraction does not leave stale extraction-owned values visible as current data.
- [ ] #3 Manual/user-owned fields that should survive reset are documented by tests or comments at the reset boundary.
- [ ] #4 Existing extraction success behavior repopulates fields normally after reset or recapture.
- [ ] #5 Focused tests cover both `JobService.resetExtraction` and the recapture path in `BackgroundStore.insertCaptureAtomically`.
<!-- AC:END -->
