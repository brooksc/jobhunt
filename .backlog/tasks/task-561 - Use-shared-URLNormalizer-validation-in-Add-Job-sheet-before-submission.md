---
id: TASK-561
title: Use shared URLNormalizer validation in Add Job sheet before submission
status: To Do
assignee: []
created_date: '2026-06-20 00:17'
labels:
  - audit
  - capture-ingestion
  - ui
  - validation
dependencies: []
references:
  - 'app/Views/Jobs/AddJobSheet.swift:39'
  - 'core/Services/JobService.swift:183'
  - 'core/Services/URLNormalizer.swift:19'
modified_files:
  - app/Views/Jobs/AddJobSheet.swift
  - core/Services/URLNormalizer.swift
  - tests/CoreTests/URLNormalizerTests.swift
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: `AddJobSheet.submit()` checks `URL(string: url) != nil` before submitting (`app/Views/Jobs/AddJobSheet.swift:39`). `URL(string:)` accepts relative/schemeless strings that the actual ingestion policy rejects. The service then applies the real shared policy with `URLNormalizer.validatedForIngestion` (`core/Services/JobService.swift:183`, `core/Services/URLNormalizer.swift:19`).

Why important: persistence is protected by the service, but the UI can enable and submit inputs such as `example.com/jobs` that are guaranteed to fail later. That creates a slower, less clear user flow and keeps a second definition of "valid URL" in the app despite the completed centralized URL-validation work.

Suggested implementation: have the sheet call `URLNormalizer.validatedForIngestion` for client-side validation and show the same user-facing rule as the service: a valid `http` or `https` web address is required. Keep service validation as the authoritative guard. Add a small UI/helper test if URL validation is factored out; otherwise add a focused unit test around the helper used by the sheet.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The Add Job sheet rejects schemeless and non-http(s) input before starting the async save.
- [ ] #2 The sheet and `JobService.addJobByURL` use the same URL validation policy.
- [ ] #3 The user-facing error clearly says an `http` or `https` web address is required.
<!-- AC:END -->
