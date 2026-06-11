---
id: TASK-169
title: 'Error handling: Report CSV export failures'
status: To Do
assignee: []
created_date: '2026-06-11 21:43'
labels:
  - audit
  - error-handling
  - export
dependencies: []
references:
  - app/Views/Jobs/JobsView.swift
  - app/JobhuntApp.swift
  - core/Services/ExportService.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CSV export writes use `try? ExportService.write` from both the Jobs view and the app command. A failed save currently looks identical to success. Replace silent writes with do/catch handling that reports failures through the chosen error UI and preserves the existing save panel flow.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 CSV write failures from the Jobs view are visible to the user.
- [ ] #2 CSV write failures from the app menu export command are visible to the user.
- [ ] #3 The export flow distinguishes user cancellation from write failure.
<!-- AC:END -->
