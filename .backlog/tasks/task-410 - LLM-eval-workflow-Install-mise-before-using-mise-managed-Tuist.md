---
id: TASK-410
title: 'LLM eval workflow: Install mise before using mise-managed Tuist'
status: Done
assignee: []
created_date: '2026-06-13 02:01'
updated_date: '2026-06-15 06:42'
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
modified_files:
  - .github/workflows/llm-eval.yml
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The LLM eval workflow runs `mise install tuist` without first installing mise or adding it to PATH, unlike the main Swift build workflow. Make the scheduled/manual LLM eval lane self-contained and consistent with normal CI tooling setup.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 LLM eval workflow installs mise or uses an equivalent pinned setup before running `mise install`.
- [x] #2 The workflow can run on a fresh GitHub macOS runner without relying on preinstalled mise state.
- [x] #3 LLM eval uses the pinned Tuist version from `.mise.toml`.
- [x] #4 Workflow comments accurately describe the setup sequence.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
llm-eval.yml ran `mise install tuist` with no mise installed on the runner. Added an "Install mise" step (curl mise.run + add ~/.local/bin to PATH) followed by `mise install` (installs the pinned .mise.toml toolchain incl. Tuist), matching swift-build.yml exactly (AC#1/#2/#3). Step names/comments describe the sequence (AC#4). YAML validated.
<!-- SECTION:FINAL_SUMMARY:END -->
