---
id: TASK-155
title: >-
  LLM: Make LLMEval exercise the production ExtractionEngine with optional
  accuracy thresholds
status: Done
assignee: []
created_date: '2026-06-11 19:32'
updated_date: '2026-06-11 21:19'
labels:
  - llm
  - tests
  - eval
dependencies: []
references:
  - tests/LLMEval/EvalHarness.swift
  - tests/LLMEval/README.md
  - core/LLM/ExtractionEngine.swift
modified_files:
  - tests/LLMEval/EvalHarness.swift
  - tests/LLMEval/README.md
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

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Rewrote `runExtraction` to call `ExtractionEngine.extract` with a `JobExtractionSnapshot`, exercising production repair/normalization/confidence. Score functions now read from typed `ExtractionResult` fields. Added `JOBHUNT_LLM_MIN_ACCURACY` env var for threshold mode that fails the test when overall accuracy is below the configured percentage. README documents both modes.
<!-- SECTION:FINAL_SUMMARY:END -->
