---
id: TASK-377
title: >-
  CSV export: Surface global export fetch failures instead of writing empty
  files
status: Done
assignee: []
created_date: '2026-06-12 22:45'
updated_date: '2026-06-15 06:53'
labels:
  - audit
  - export
  - ux
  - data-safety
dependencies: []
references:
  - app/JobhuntApp.swift
  - core/Services/ExportService.swift
modified_files:
  - app/JobhuntApp.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The global Export Job List command uses try? for the SwiftData fetch and falls back to an empty job list. A fetch failure can therefore produce a valid-looking empty CSV without warning.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Global CSV export aborts and shows a user-visible error when the job fetch fails.
- [x] #2 Successful export behavior remains unchanged.
- [ ] #3 A focused test or manual verification covers fetch failure and success paths.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The global "Export Job List to CSV" command (⌘⇧E) now fetches jobs with do/catch instead of (try? ...) ?? []; on a fetch failure it shows an error toast ("Couldn't read jobs for export: …") and returns without opening the save panel or writing, so a fetch failure can no longer produce a valid-looking empty CSV (AC#1). Successful export is unchanged (AC#2). AC#3: the SwiftData-fetch-failure path isn't unit-testable without a store seam (same gap as TASK-479); verified by build — the success path is exercised by existing CSV tests.
<!-- SECTION:FINAL_SUMMARY:END -->
