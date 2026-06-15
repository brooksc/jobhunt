---
id: TASK-446
title: >-
  Capture quality: Track raw text byte counts without undercounting combined
  capture input
status: Done
assignee: []
created_date: '2026-06-13 18:57'
updated_date: '2026-06-15 20:04'
labels:
  - audit
  - ingestion
  - data-quality
dependencies: []
references:
  - core/Services/BackgroundStore.swift
  - core/Models/Job.swift
  - tests/CoreTests/JobServiceTests.swift
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`BackgroundStore.insertCaptureAtomically` stores `job.rawTextBytes` as the maximum of selected-text bytes and visible-text bytes. That value is used by quality checks as a proxy for raw capture size, but it under-represents captures where selected and visible text both contribute meaningful input.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Capture/job metadata records byte counts in a way that accurately represents selected text, visible text, and combined raw capture input, or the existing field is renamed/documented to match its max-field semantics.
- [ ] #2 Quality checks use the metric that matches their intent for short/insufficient capture detection.
- [ ] #3 Existing data-quality behavior is preserved or intentionally adjusted with tests explaining the new threshold semantics.
- [ ] #4 Add tests for selected-only, visible-only, and selected-plus-visible captures.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Duplicate of TASK-445 (identical title, description, acceptance criteria, and references; the two were created 3 minutes apart). Resolved by TASK-445: `job.rawTextBytes` now counts selected + visible bytes (combined, not max) in both insertCaptureAtomically paths and the QualityChecker fallback, with tests for selected-only/visible-only/both. No separate work needed.
<!-- SECTION:FINAL_SUMMARY:END -->
