---
id: TASK-158
title: 'Data integrity: Make manual Add Job use a valid ingestion path'
status: Done
assignee: []
created_date: '2026-06-11 20:55'
updated_date: '2026-06-11 21:07'
labels:
  - audit
  - data-integrity
  - workflow
  - macos
dependencies: []
references:
  - app/Views/Jobs/AddJobSheet.swift
  - core/Services/JobService.swift
modified_files:
  - core/Services/JobService.swift
  - app/Views/Jobs/AddJobSheet.swift
  - tests/CoreTests/JobServiceTests.swift
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

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added `JobService.addJobByURL(_:)` that uses the URL itself as synthetic pageTitle/visibleText so the LLM extraction has content to parse. Updated AddJobSheet.submit() to call the new method. Three tests cover success, duplicate detection, and invalid URL error.
<!-- SECTION:FINAL_SUMMARY:END -->
