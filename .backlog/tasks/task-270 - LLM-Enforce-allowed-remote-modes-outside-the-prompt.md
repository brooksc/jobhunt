---
id: TASK-270
title: 'LLM: Enforce allowed remote modes outside the prompt'
status: To Do
assignee: []
created_date: '2026-06-12 03:26'
labels:
  - audit
  - llm
  - normalization
  - location
dependencies: []
references:
  - core/LLM/PromptBuilder.swift
  - core/LLM/ExtractionEngine.swift
  - core/LLM/Normalization.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Allowed remote/hybrid/onsite modes are included only as prompt context. Normalization receives preferred locations but not allowed mode constraints, so disallowed modes can still be extracted and persisted. Add deterministic validation/filtering after model extraction or clearly rename the setting if it is only prompt guidance.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Location mode allow/disallow settings are enforced deterministically after extraction, or the setting is explicitly documented/renamed as prompt-only guidance.
- [ ] #2 Tests cover remote, hybrid, and onsite outputs when each mode is disallowed.
- [ ] #3 User-visible extraction state explains when a posting is rejected or marked incompatible due to mode constraints.
<!-- AC:END -->
