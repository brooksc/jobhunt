---
id: TASK-322
title: 'OpenRouter: Wire or remove free-model rotation setting'
status: To Do
assignee: []
created_date: '2026-06-12 20:01'
labels:
  - audit
  - llm-provider
  - openrouter
dependencies: []
references:
  - core/Settings/SettingsStore.swift
  - core/LLM/LLMProviderFactory.swift
  - core/LLM/Providers/OpenRouterProvider.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
llmOpenRouterFreeRotate and OpenRouterRotationPool exist, but no production caller uses them. OpenRouterProvider always uses the configured model path.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 If free-model rotation is supported, OpenRouterProvider/queue processing uses OpenRouterRotationPool when llmOpenRouterFreeRotate is enabled.
- [ ] #2 If unsupported, remove or hide the setting and unused rotation code.
- [ ] #3 Tests cover enabled rotation, stale/fetch failure behavior, and disabled static-model behavior.
<!-- AC:END -->
