---
id: TASK-157
title: 'LLM: Wire or remove OpenRouter free-tier model rotation'
status: To Do
assignee: []
created_date: '2026-06-11 19:32'
labels:
  - llm
  - openrouter
  - settings
dependencies: []
references:
  - app/Views/Settings/SettingsView.swift
  - core/LLM/LLMProviderFactory.swift
  - core/LLM/Providers/OpenRouterProvider.swift
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
LLM/extraction audit finding: Settings exposes an OpenRouter free-tier rotation toggle and Core has `OpenRouterRotationPool`, but no request path appears to call `next()` or select rotated models. The UI likely advertises behavior that does not happen.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 If the feature is kept, OpenRouter requests use the rotation pool when the setting is enabled and fall back predictably when the pool is empty.
- [ ] #2 If the feature is deferred, the toggle is hidden or clearly disabled so users are not misled.
- [ ] #3 Tests cover model selection with rotation enabled, disabled, empty pool, and stale refresh failure.
- [ ] #4 Attempt metadata records the actual rotated model requested/returned.
<!-- AC:END -->
