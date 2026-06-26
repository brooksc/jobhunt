---
id: TASK-538
title: 'LLM: persist actual provider token usage for cost and diagnostics'
status: Done
assignee: []
created_date: '2026-06-19 04:57'
updated_date: '2026-06-26 07:27'
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
- [x] #1 `ExtractionResult` and `FitScoreOutput` carry optional prompt/completion token counts from `ChatResponse`.
- [x] #2 `LLMRequestAttempt` persists optional prompt/completion token counts with schema evolution coverage.
- [x] #3 Successful extraction and fit attempts save token counts when the provider returns usage metadata.
- [x] #4 Character counts remain persisted and are used as fallback when token usage is unavailable.
- [x] #5 Debug or cost diagnostics can show actual token usage totals/averages when present.
- [x] #6 Provider and queue tests cover at least one OpenAI-compatible response and one non-OpenAI provider response with token metadata.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ExtractionResult and FitScoreOutput now carry optional promptTokens/completionTokens populated from ChatResponse (AC#1). LLMRequestAttempt gained promptTokens/completionTokens — additive optional fields, so a lightweight SwiftData migration (no new VersionedSchema); both schema-stability guards (name + type) updated per the checklist (AC#2). QueueActor passes them on successful extract and fit recordAttempt calls (AC#3). promptChars/responseChars remain persisted as the fallback for providers that don't report usage (AC#4). The Debug tab LLM Stats section shows prompt/completion token avg/max when any attempt has usage (AC#5). Tests: testExtractionPropagatesProviderTokenUsage (engine), OpenAI + Anthropic ChatResponse token assertions (AC#6), and the schema guards pin the new fields. Full fast gate (Core/Server/MCP) green; lint clean. Commit 4bd8ec5.
<!-- SECTION:FINAL_SUMMARY:END -->
