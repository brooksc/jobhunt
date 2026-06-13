---
id: TASK-453
title: 'Fit scoring: Validate LLM dimension schema before persisting scores'
status: To Do
assignee: []
created_date: '2026-06-13 22:02'
labels:
  - bug
  - llm
  - fit-scoring
dependencies: []
references:
  - core/LLM/ExtractionEngine.swift
  - core/Services/FitScorer.swift
  - tests/CoreTests/ExtractionEngineTests.swift
  - tests/CoreTests/FitScorerTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Fit scoring currently accepts any dimension names returned by the LLM and lets missing expected dimensions score as zero. A malformed response such as `{"dimensions":[{"name":"Technical","score":75}]}` can be stored as a successful but misleading low score instead of a retryable schema failure. Fit scoring should validate the exact expected dimension contract before computing and persisting a score.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Fit scoring requires exactly the expected dimension names: `required_qualifications`, `preferred_qualifications`, `skills`, `experience_level`, and `domain_fit`.
- [ ] #2 Unknown, missing, duplicated, or non-numeric dimension scores produce a clear invalid-response error instead of a successful fit score.
- [ ] #3 Valid fit responses continue to compute the same weighted scores as today.
- [ ] #4 Focused tests cover unknown dimension names, missing dimensions, duplicate dimensions, non-numeric scores, and a valid response.
<!-- AC:END -->
