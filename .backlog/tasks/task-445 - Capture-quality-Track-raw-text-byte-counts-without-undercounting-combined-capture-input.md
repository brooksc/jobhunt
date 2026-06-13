---
id: TASK-445
title: >-
  Capture quality: Track raw text byte counts without undercounting combined
  capture input
status: To Do
assignee: []
created_date: '2026-06-13 18:54'
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
