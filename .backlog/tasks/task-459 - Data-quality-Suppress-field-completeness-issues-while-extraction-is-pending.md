---
id: TASK-459
title: 'Data quality: Suppress field-completeness issues while extraction is pending'
status: To Do
assignee: []
created_date: '2026-06-13 23:35'
labels:
  - data-quality
  - extraction
  - ux
dependencies: []
references:
  - core/Models/QualityIssue.swift
  - app/Views/Quality/DataQualityView.swift
  - tests/CoreTests/QualityCheckerTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`QualityChecker.issues` evaluates missing company, title, location, work mode, and salary before adding `.extractionPending`. New jobs default to pending extraction, so they can show multiple missing-field issues before extraction has run. Quality reporting should avoid mixing expected pending-state gaps with real data-quality defects.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Pending extraction jobs report the pending extraction state without also reporting field-completeness issues caused by missing extracted fields.
- [ ] #2 Failed extraction behavior remains actionable and still exposes appropriate failure and/or field issues according to the chosen product semantics.
- [ ] #3 Succeeded extraction jobs continue to report missing company/title/location/work mode/salary when those fields remain missing.
- [ ] #4 Tests cover pending, failed, and succeeded extraction states with missing fields.
<!-- AC:END -->
