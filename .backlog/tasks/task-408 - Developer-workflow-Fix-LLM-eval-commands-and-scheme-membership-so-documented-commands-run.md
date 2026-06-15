---
id: TASK-408
title: >-
  Developer workflow: Fix LLM eval commands and scheme membership so documented
  commands run
status: Done
assignee: []
created_date: '2026-06-13 01:57'
updated_date: '2026-06-15 06:42'
labels:
  - audit
  - developer-workflow
  - tests
  - llm-eval
dependencies: []
references:
  - Project.swift
  - README.md
  - CONTRIBUTING.md
  - Tests/LLMEval/README.md
  - .github/workflows/llm-eval.yml
modified_files:
  - README.md
  - CONTRIBUTING.md
  - .github/workflows/llm-eval.yml
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
README, CONTRIBUTING, and LLMEval docs tell developers to run `xcodebuild test -scheme Jobhunt-DMG -only-testing:LLMEval`, but LLMEval is not part of the Jobhunt-DMG scheme test action. The generated standalone LLMEval scheme works. Align the scheme and docs so local and CI LLM eval commands are executable.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The documented LLM eval command succeeds in test enumeration without 'not a member of scheme' errors.
- [x] #2 README, CONTRIBUTING, LLMEval README, and CI use the same intended LLM eval scheme or clearly document the difference.
- [x] #3 Project.swift either includes LLMEval in the intended app scheme test action or documents and exposes the standalone LLMEval scheme as the canonical path.
- [x] #4 A smoke command for LLM eval is added to contributor/release docs.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
README/CONTRIBUTING told developers to run LLMEval under -scheme Jobhunt-DMG, which doesn't include LLMEval in its test action ("not a member of scheme"); CI used -scheme LLMEval; only tests/LLMEval/README used the correct Jobhunt-Eval. Standardized all four on the opt-in Jobhunt-Eval scheme (the canonical one Project.swift builds for the LLM benchmark) (AC#2/#3). Verified `xcodebuild build-for-testing -scheme Jobhunt-Eval` succeeds — test enumeration works with no scheme-membership error (AC#1). The smoke command (with JOBHUNT_LLM_URL) is in README/CONTRIBUTING/tests/LLMEval/README (AC#4). Note: could not run the eval itself (needs a real OpenAI-compatible endpoint/keys).
<!-- SECTION:FINAL_SUMMARY:END -->
