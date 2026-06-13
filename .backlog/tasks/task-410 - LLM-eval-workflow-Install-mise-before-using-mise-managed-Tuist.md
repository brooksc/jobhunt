---
id: TASK-410
title: 'LLM eval workflow: Install mise before using mise-managed Tuist'
status: To Do
assignee: []
created_date: '2026-06-13 02:01'
labels:
  - audit
  - ci
  - developer-workflow
  - llm-eval
  - tooling
dependencies: []
references:
  - .github/workflows/llm-eval.yml
  - .github/workflows/swift-build.yml
  - .mise.toml
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The LLM eval workflow runs `mise install tuist` without first installing mise or adding it to PATH, unlike the main Swift build workflow. Make the scheduled/manual LLM eval lane self-contained and consistent with normal CI tooling setup.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 LLM eval workflow installs mise or uses an equivalent pinned setup before running `mise install`.
- [ ] #2 The workflow can run on a fresh GitHub macOS runner without relying on preinstalled mise state.
- [ ] #3 LLM eval uses the pinned Tuist version from `.mise.toml`.
- [ ] #4 Workflow comments accurately describe the setup sequence.
<!-- AC:END -->
