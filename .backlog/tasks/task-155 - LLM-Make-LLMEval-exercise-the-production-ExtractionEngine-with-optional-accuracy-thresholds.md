---
id: TASK-155
title: >-
  LLM: Make LLMEval exercise the production ExtractionEngine with optional
  accuracy thresholds
status: To Do
assignee: []
created_date: '2026-06-11 19:32'
labels:
  - llm
  - tests
  - eval
dependencies: []
references:
  - tests/LLMEval/EvalHarness.swift
  - tests/LLMEval/README.md
  - core/LLM/ExtractionEngine.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
LLM/extraction audit finding: the LLMEval harness builds prompts and parses JSON directly instead of calling `ExtractionEngine.extract`, and it intentionally never fails on poor accuracy. This is useful for reporting but weak as a regression guard.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 LLMEval runs fixture jobs through `ExtractionEngine.extract` so production repair, normalization, confidence, and field mapping are exercised.
- [ ] #2 The harness retains a reporting mode that skips gracefully when no provider is configured.
- [ ] #3 An opt-in threshold mode fails when field accuracy falls below a configured minimum.
- [ ] #4 README documents reporting mode versus threshold/release-check mode.
<!-- AC:END -->
