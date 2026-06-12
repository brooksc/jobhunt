---
id: TASK-254
title: 'Domain correctness: Validate complete fit-score dimensions before scoring'
status: Done
assignee: []
created_date: '2026-06-12 02:42'
updated_date: '2026-06-12 03:09'
labels:
  - audit
  - domain
  - fit-scoring
  - llm
dependencies: []
references:
  - core/Services/FitScorer.swift
  - core/LLM/ExtractionEngine.swift
  - tests/CoreTests/FitScorerTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`FitScorer.computeScore` normalizes by weights present, so a partial LLM response with only one high-scoring dimension can produce an inflated overall score. Existing tests lock in this partial-normalization behavior, but it weakens the domain meaning of fit scores.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Fit scoring requires all expected dimensions, penalizes missing dimensions, or marks partial responses invalid according to a documented rule.
- [ ] #2 Tests cover missing dimensions, empty dimensions, malformed LLM fit output, and rescore-from-JSON behavior.
- [ ] #3 Stored fit-score JSON records enough information to distinguish complete scores from degraded or invalid partial scores.
<!-- AC:END -->
