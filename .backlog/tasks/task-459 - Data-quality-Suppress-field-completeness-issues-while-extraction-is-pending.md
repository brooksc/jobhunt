---
id: TASK-459
title: 'Data quality: Suppress field-completeness issues while extraction is pending'
status: Done
assignee: []
created_date: '2026-06-13 23:35'
updated_date: '2026-06-15 18:10'
labels:
  - data-quality
  - extraction
  - ux
dependencies: []
references:
  - core/Models/QualityIssue.swift
  - app/Views/Quality/DataQualityView.swift
  - tests/CoreTests/QualityCheckerTests.swift
modified_files:
  - core/Models/QualityIssue.swift
  - tests/CoreTests/QualityCheckerTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`QualityChecker.issues` evaluates missing company, title, location, work mode, and salary before adding `.extractionPending`. New jobs default to pending extraction, so they can show multiple missing-field issues before extraction has run. Quality reporting should avoid mixing expected pending-state gaps with real data-quality defects.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Pending extraction jobs report the pending extraction state without also reporting field-completeness issues caused by missing extracted fields.
- [x] #2 Failed extraction behavior remains actionable and still exposes appropriate failure and/or field issues according to the chosen product semantics.
- [x] #3 Succeeded extraction jobs continue to report missing company/title/location/work mode/salary when those fields remain missing.
- [x] #4 Tests cover pending, failed, and succeeded extraction states with missing fields.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
QualityChecker.issues now gates the missing-extracted-field checks (company/title/location/work mode/salary) behind `extractionStatus != .pending`, so a pending job reports .extractionPending (plus genuine capture-size issues) but not the expected-missing-field gaps (AC#1). Failed jobs still report .extractionFailed AND field gaps (kept actionable, AC#2); succeeded jobs still report missing fields (AC#3). Tests cover pending (fields suppressed), succeeded (fields reported), and failed (failure + fields) (AC#4).
<!-- SECTION:FINAL_SUMMARY:END -->
