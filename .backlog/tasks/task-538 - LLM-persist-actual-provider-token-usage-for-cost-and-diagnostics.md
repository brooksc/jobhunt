---
id: TASK-538
title: 'LLM: persist actual provider token usage for cost and diagnostics'
status: To Do
assignee: []
created_date: '2026-06-19 04:57'
labels:
  - audit
  - llm
  - cost
  - telemetry
  - provider
dependencies: []
references:
  - core/LLM/LLMProvider.swift
  - core/LLM/ExtractionEngine.swift
  - core/LLM/QueueActor.swift
  - core/Models/LLMRequestAttempt.swift
  - core/LLM/CostEstimator.swift
  - app/Views/Settings/DebugTab.swift
  - tests/CoreTests/ExtractionEngineTests.swift
  - tests/CoreTests/LLMProviderTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: provider adapters already parse token usage into `ChatResponse.promptTokens` and `ChatResponse.completionTokens` for OpenAI-compatible, Anthropic, and Google responses, but `ExtractionEngine` drops those fields and `QueueActor` persists only `promptChars`/`responseChars` on `LLMRequestAttempt`. The cost UI uses rough character-based estimates and debug stats show character counts, not actual billed/usage tokens when providers supply them.

Why this matters: this is a cost-control boundary. Character estimates are useful before work runs, but after cloud calls complete the app should retain actual provider-reported usage for auditability, provider comparison, and debugging unexpectedly expensive runs. Dropping token counts also makes it harder to validate prompt-size changes against real provider behavior.

Suggested implementation: add optional `promptTokens` and `completionTokens` fields to extraction/fit outputs and `LLMRequestAttempt`, wire them through from `ChatResponse`, and persist them for successful attempts when available. Keep character counts as a fallback and for providers that do not report usage. Update debug/cost surfaces to prefer actual token totals where present, while preserving estimates for preflight cost projection.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `ExtractionResult` and `FitScoreOutput` carry optional prompt/completion token counts from `ChatResponse`.
- [ ] #2 `LLMRequestAttempt` persists optional prompt/completion token counts with schema evolution coverage.
- [ ] #3 Successful extraction and fit attempts save token counts when the provider returns usage metadata.
- [ ] #4 Character counts remain persisted and are used as fallback when token usage is unavailable.
- [ ] #5 Debug or cost diagnostics can show actual token usage totals/averages when present.
- [ ] #6 Provider and queue tests cover at least one OpenAI-compatible response and one non-OpenAI provider response with token metadata.
<!-- AC:END -->
