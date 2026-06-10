---
id: TASK-098
title: Extract typed job-detail projection logic out of SwiftUI views
status: To Do
assignee: []
created_date: '2026-06-10 07:49'
labels:
  - audit
  - refactor
  - ui
dependencies: []
references:
  - app/Views/Detail/JobDetailView.swift
  - core/Models/Job.swift
  - core/LLM/ExtractionEngine.swift
  - core/Services/FitScorer.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Audit finding: `JobDetailView.swift` mixes rendering with JSON parsing, salary/fit display formatting, skill override handling, and service calls. Move typed derived data for job detail display behind a small projection/view-model boundary so schema and formatting changes do not require editing large SwiftUI view bodies.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Job detail views consume typed projection values for extracted summary, requirements, nice-to-haves, skills, salary display, and fit display instead of parsing raw JSON directly in view bodies.
- [ ] #2 Salary and fit display rules used by the detail header and overview/fit tabs are centralized so duplicate formatting logic is removed.
- [ ] #3 Tests cover projection behavior for valid JSON, missing JSON, malformed JSON, and manual skill overrides.
- [ ] #4 User-visible Job Detail behavior remains unchanged except for any intentional bug fixes documented in the task notes.
<!-- AC:END -->
