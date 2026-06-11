---
id: TASK-185
title: 'Test quality: Add a thresholded LLM evaluation lane'
status: To Do
assignee: []
created_date: '2026-06-11 22:19'
labels:
  - audit
  - tests
  - llm
  - ci
dependencies: []
references:
  - tests/LLMEval/EvalHarness.swift
  - tests/LLMEval/README.md
  - README.md
  - .github/workflows
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
LLMEval is valuable for extraction quality, but it skips without provider configuration and passes in reporting mode unless `JOBHUNT_LLM_MIN_ACCURACY` is set. Add a scheduled/manual lane with known provider setup and an explicit accuracy threshold so extraction quality drift is visible before release.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A documented scheduled or manual workflow runs LLMEval with `JOBHUNT_LLM_MIN_ACCURACY` set.
- [ ] #2 The lane records or publishes the eval score so quality drift is visible over time.
- [ ] #3 The default local reporting mode remains available for exploratory runs.
<!-- AC:END -->
