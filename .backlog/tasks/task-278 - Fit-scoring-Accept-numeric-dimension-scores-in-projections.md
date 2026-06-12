---
id: TASK-278
title: 'Fit scoring: Accept numeric dimension scores in projections'
status: To Do
assignee: []
created_date: '2026-06-12 03:34'
labels:
  - audit
  - fit-scoring
  - projection
  - ui
dependencies: []
references:
  - core/Models/Projections.swift
  - tests/CoreTests/ProjectionsTests.swift
  - core/Services/FitScorer.swift
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
FitScoreProjection only accepts Int dimension scores even though LLM JSON and FitScorer support Double values. Numeric scores encoded as Double are silently dropped from the UI projection.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 FitScoreProjection accepts both Int and Double dimension scores.
- [ ] #2 Projection tests cover integer and floating-point score values.
- [ ] #3 UI rounds or formats projected scores consistently with FitScorer.
<!-- AC:END -->
