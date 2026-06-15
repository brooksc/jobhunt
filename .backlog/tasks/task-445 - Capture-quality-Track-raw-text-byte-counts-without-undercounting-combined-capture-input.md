---
id: TASK-445
title: >-
  Capture quality: Track raw text byte counts without undercounting combined
  capture input
status: Done
assignee: []
created_date: '2026-06-13 18:54'
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
- [x] #1 Capture/job metadata records byte counts in a way that accurately represents selected text, visible text, and combined raw capture input, or the existing field is renamed/documented to match its max-field semantics.
- [x] #2 Quality checks use the metric that matches their intent for short/insufficient capture detection.
- [x] #3 Existing data-quality behavior is preserved or intentionally adjusted with tests explaining the new threshold semantics.
- [x] #4 Add tests for selected-only, visible-only, and selected-plus-visible captures.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
`job.rawTextBytes` now stores the total transmitted raw bytes (selectedText + visibleText) instead of `max(selected, visible)` — fixed in both `insertCaptureAtomically` paths (new-capture and update-existing) and the `QualityChecker.rawByteSize` fallback. The cleaner uses both inputs, so `max` undercounted captures where both contribute (a 600+600 capture stored 600 and could be falsely flagged `.shortRawText`). This raw count reflects capture-pipeline size; deduped unique content stays the separate `cleanedTextBytes`/`.shortCleanedText` check (AC#2). Intentional adjustment (AC#3): captures whose combined input crosses the threshold are no longer flagged short — documented; old rows keep their cached max value (a coarse proxy not worth a backfill). AC#4: tests for selected-only (300), visible-only (400), and selected+visible (1200, not undercounted, not flagged). Full CoreTests (765) green; app builds.
<!-- SECTION:FINAL_SUMMARY:END -->
