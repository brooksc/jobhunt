---
id: TASK-098
title: Extract typed job-detail projection logic out of SwiftUI views
status: Done
assignee: []
created_date: '2026-06-10 07:49'
updated_date: '2026-06-11 02:33'
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

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Created core/Models/Projections.swift with JobDetailProjection (summary, requirements, niceToHaves, skills from extractedJSON + manualOverridesJSON), FitScoreProjection (requirementsMet, requirementsNotMet, dimensions from fitScoreJSON), and SalaryDisplay.text() helper. Removed all inline JSONSerialization calls from JobDetailView; consolidated the two duplicate salaryText computed vars into one-liners. Added 17 tests covering populated JSON, missing JSON, malformed JSON, manual override precedence, and all salary display branches.
<!-- SECTION:FINAL_SUMMARY:END -->
