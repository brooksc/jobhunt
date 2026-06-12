---
id: TASK-348
title: 'LLM eval: Align docs and commands with actual environment contract'
status: To Do
assignee: []
created_date: '2026-06-12 20:39'
labels:
  - audit
  - tests
  - docs
  - llm-eval
dependencies: []
references:
  - README.md
  - CONTRIBUTING.md
  - tests/LLMEval/EvalHarness.swift
  - tests/LLMEval/README.md
  - .github/workflows/llm-eval.yml
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
README and CONTRIBUTING show LLM_EVAL=1 for local eval, but LLMEvalHarness skips unless JOBHUNT_LLM_URL is set and only fails when JOBHUNT_LLM_MIN_ACCURACY is set. Developers can run the documented command and get a skipped/non-gating result.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 README and CONTRIBUTING document JOBHUNT_LLM_URL and threshold mode consistently with LLMEvalHarness.
- [ ] #2 Either LLM_EVAL is removed from docs or wired to meaningful behavior.
- [ ] #3 A local eval command that should gate accuracy fails below the configured threshold instead of silently reporting/skipping.
<!-- AC:END -->
