---
id: TASK-158
title: 'Data integrity: Make manual Add Job use a valid ingestion path'
status: To Do
assignee: []
created_date: '2026-06-11 20:55'
labels:
  - audit
  - data-integrity
  - workflow
  - macos
dependencies: []
references:
  - app/Views/Jobs/AddJobSheet.swift
  - core/Services/JobService.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The manual Add Job flow constructs `CapturePayload(url: pageTitle: visibleText:)` with empty title and text, but `JobService.ingestCapture` rejects missing page titles and missing captured text. The UI therefore appears unable to add a job by URL alone. Add a URL-only ingestion path, fetch page metadata/content before ingesting, or change the UI to require/provide the fields the service validates.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Manual Add Job succeeds for a valid URL or presents field-level validation before submission.
- [ ] #2 The service path used by Add Job satisfies `JobService.ingestCapture` validation or uses an explicit URL-only API with its own semantics.
- [ ] #3 Failure messages shown by Add Job are user-readable and covered by a focused test or UI-level check.
<!-- AC:END -->
