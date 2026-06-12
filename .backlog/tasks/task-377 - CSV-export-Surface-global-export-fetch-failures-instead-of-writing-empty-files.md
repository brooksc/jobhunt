---
id: TASK-377
title: >-
  CSV export: Surface global export fetch failures instead of writing empty
  files
status: To Do
assignee: []
created_date: '2026-06-12 22:45'
labels:
  - audit
  - export
  - ux
  - data-safety
dependencies: []
references:
  - app/JobhuntApp.swift
  - core/Services/ExportService.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The global Export Job List command uses try? for the SwiftData fetch and falls back to an empty job list. A fetch failure can therefore produce a valid-looking empty CSV without warning.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Global CSV export aborts and shows a user-visible error when the job fetch fails.
- [ ] #2 Successful export behavior remains unchanged.
- [ ] #3 A focused test or manual verification covers fetch failure and success paths.
<!-- AC:END -->
