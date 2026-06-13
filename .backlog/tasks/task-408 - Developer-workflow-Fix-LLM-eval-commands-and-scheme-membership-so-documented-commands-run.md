---
id: TASK-408
title: >-
  Developer workflow: Fix LLM eval commands and scheme membership so documented
  commands run
status: To Do
assignee: []
created_date: '2026-06-13 01:57'
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
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
README, CONTRIBUTING, and LLMEval docs tell developers to run `xcodebuild test -scheme Jobhunt-DMG -only-testing:LLMEval`, but LLMEval is not part of the Jobhunt-DMG scheme test action. The generated standalone LLMEval scheme works. Align the scheme and docs so local and CI LLM eval commands are executable.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The documented LLM eval command succeeds in test enumeration without 'not a member of scheme' errors.
- [ ] #2 README, CONTRIBUTING, LLMEval README, and CI use the same intended LLM eval scheme or clearly document the difference.
- [ ] #3 Project.swift either includes LLMEval in the intended app scheme test action or documents and exposes the standalone LLMEval scheme as the canonical path.
- [ ] #4 A smoke command for LLM eval is added to contributor/release docs.
<!-- AC:END -->
