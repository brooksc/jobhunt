---
id: TASK-298
title: 'Availability: Restrict auto-expiry to appropriate job statuses'
status: To Do
assignee: []
created_date: '2026-06-12 05:01'
labels:
  - audit
  - availability
  - jobs
dependencies: []
references:
  - app/Views/Settings/SettingsTab.swift
  - core/Services/AvailabilityChecker.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Manual availability checking only examines pursuing jobs, but the automatic stale path skips only passed, archived, closed, and expired. This can mark new, applied, interview, offer, rejected, or duplicate jobs as expired.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Define the allowed statuses for automatic availability expiry and align checkStaleJobs/checkJobs with that policy.
- [ ] #2 Jobs in protected workflow states such as applied, interview, offer, rejected, and duplicate are not auto-expired unless explicitly intended.
- [ ] #3 Add regression tests for statuses that must not be auto-expired.
<!-- AC:END -->
