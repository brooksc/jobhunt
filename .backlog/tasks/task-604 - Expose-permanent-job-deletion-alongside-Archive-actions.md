---
id: TASK-604
title: Expose permanent job deletion alongside Archive actions
status: To Do
assignee: []
created_date: '2026-07-21 21:42'
labels:
  - workflow
  - ux
  - jobs
dependencies: []
references:
  - app/ContentView.swift
  - app/Views/Jobs/JobsView.swift
  - app/Views/Detail/JobDetailView.swift
  - app/Shell/AppCommands.swift
  - core/Services/JobService.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Permanent job deletion already exists through the row context menu, Job menu, Delete key, and Raw tab, but the prominent selection actions emphasize Archive and do not expose Delete. Add a discoverable destructive Delete option alongside Archive for removing captures that are not actually job descriptions. Reuse JobService.delete and the existing permanent-delete confirmation rather than introducing another deletion path.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The primary selected-job action surface exposes Delete alongside Archive for both single and multiple selected jobs.
- [ ] #2 Delete requires explicit destructive confirmation that states the job and its related captured data will be permanently removed.
- [ ] #3 Confirming deletion uses the existing JobService.delete path, removes all selected jobs, clears stale selection, and reports partial or complete failures without claiming success.
- [ ] #4 Archive remains available as the reversible workflow option and its behavior is unchanged.
- [ ] #5 Focused UI or service-level coverage verifies delete confirmation, cancellation, successful deletion, and failure feedback for the newly exposed action.
<!-- AC:END -->
