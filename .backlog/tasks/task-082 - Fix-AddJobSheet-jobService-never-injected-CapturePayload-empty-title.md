---
id: TASK-082
title: 'Fix AddJobSheet: jobService never injected + CapturePayload empty title'
status: To Do
assignee: []
created_date: '2026-06-10 07:30'
labels:
  - bug
  - ui-audit
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Two HIGH bugs that make "Add Job" completely non-functional:

1. `jobService` custom environment key is never injected anywhere in the app. `try await jobService?.ingestCapture(...)` silently returns nil, calls `dismiss()`, looks like it saved but nothing happened. Fix: inject `.environment(\.jobService, jobService)` on every sheet that needs it.

2. Even if jobService were non-nil, `CapturePayload(url: url, pageTitle: "", visibleText: "")` passes empty title. `ingestCapture()` immediately throws `.missingPageTitle`. Fix: populate `pageTitle` from the URL or let the user provide it in the sheet.

Files: `app/Views/Jobs/AddJobSheet.swift`, `app/Views/ContentView.swift` (injection site)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Adding a job via AddJobSheet actually saves a job to the database
- [ ] #2 jobService environment key is injected at ContentView level so all child sheets have access
- [ ] #3 CapturePayload is constructed with a non-empty pageTitle
- [ ] #4 Error is surfaced to user if ingest fails
<!-- AC:END -->
