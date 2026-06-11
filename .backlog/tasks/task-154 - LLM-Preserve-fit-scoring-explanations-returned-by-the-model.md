---
id: TASK-154
title: 'LLM: Preserve fit-scoring explanations returned by the model'
status: To Do
assignee: []
created_date: '2026-06-11 19:32'
labels:
  - llm
  - fit-scoring
  - ux
  - persistence
dependencies: []
references:
  - core/LLM/ExtractionEngine.swift
  - core/Services/FitScorer.swift
  - core/Models/Projections.swift
  - app/Views/Detail/JobDetailView.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
LLM/extraction audit finding: the fit-scoring path parses the model response into dimensions and requirements, then stores only the computed `FitScoreResult`. New fit scores can lose `summary`, `requirements_met`, `requirements_not_met`, dimension rationales, and other explanation fields expected by `FitScoreProjection` and the Fit tab UI.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Persisted `fitScoreJSON` retains the explanatory fields returned by the LLM, including requirements met/not met and dimension rationales.
- [ ] #2 The computed overall score, penalty, and score weights are preserved without overwriting or dropping raw explanation fields.
- [ ] #3 The Fit tab displays explanations for newly generated fit scores, not only migrated/demo scores.
- [ ] #4 Tests cover score computation and projection from a newly generated fit-scoring response.
<!-- AC:END -->
