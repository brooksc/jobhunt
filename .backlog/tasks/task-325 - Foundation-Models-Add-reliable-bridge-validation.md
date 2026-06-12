---
id: TASK-325
title: 'Foundation Models: Add reliable bridge validation'
status: To Do
assignee: []
created_date: '2026-06-12 20:02'
labels:
  - audit
  - llm-provider
  - foundation-models
dependencies: []
references:
  - core/LLM/Providers/FoundationModelsProvider.swift
  - tests/CoreTests/LLMProviderTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
FoundationModelsProvider uses Objective-C selector lookup for LanguageModelSession and tests allow success or failure on macOS 26+, so a broken bridge can pass CI.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Foundation Models bridge has deterministic tests or an injectable adapter that validates the expected API contract.
- [ ] #2 On macOS 26+, missing Apple Intelligence availability is distinguished from a broken bridge implementation.
- [ ] #3 Provider errors remain clear and sanitized for queue history.
<!-- AC:END -->
