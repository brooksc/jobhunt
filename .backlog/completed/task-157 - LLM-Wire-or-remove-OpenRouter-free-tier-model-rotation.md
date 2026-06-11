---
id: TASK-157
title: 'LLM: Wire or remove OpenRouter free-tier model rotation'
status: Done
assignee: []
created_date: '2026-06-11 19:32'
updated_date: '2026-06-11 21:42'
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

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Deferred the feature. Removed the "Free-tier model rotation" toggle from OpenRouter settings — the `OpenRouterRotationPool` actor and `llmOpenRouterFreeRotate` setting key are never called during actual extraction, so the toggle was advertising behavior that didn't happen. The pool implementation and setting key are preserved for future wiring. No tests needed for a UI removal.
<!-- SECTION:FINAL_SUMMARY:END -->
