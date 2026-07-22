---
id: TASK-607
title: >-
  llm: make max_tokens output cap model-aware (reasoning models exhaust the
  fixed 16384)
status: Done
assignee: []
created_date: '2026-07-21 23:40'
updated_date: '2026-07-22 18:05'
labels:
  - llm
  - tech-debt
  - performance
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`LLMProvider.swift:62` defaults `maxTokens: Int = 16384` and every extraction + fit `ChatRequest` (`ExtractionEngine.swift:139,264`) omits maxTokens, so all calls inherit it. It's passed straight through as the provider output cap (`OpenAICompatibleTransport.swift:125`, `AnthropicProvider.swift:42`).

Problem: one fixed number for every model. On reasoning/thinking models (OpenAI o-series/gpt-5-thinking, Gemini 2.5/3 thinking, Claude extended thinking) the reasoning tokens count against max_tokens, so the model can exhaust the budget thinking and return truncated/empty JSON → `ExtractionEngineError.invalidJSON` → retry_exhausted (same failure shape as job #273). Same class as the maxResumeChars=12000 legacy carryover.

Cannot be blindly raised: some providers error if max_tokens exceeds a model's output limit, and Anthropic REQUIRES the field. Needs the model-aware treatment — reuse/extend the context-window registry idea (Gemini `outputTokenLimit`, OpenRouter `/models`, Ollama `/api/show`) to set a per-model output budget (e.g. min(model_max_output, sensible_ceiling)), with a safe fallback for unknown models.

Ties to the same registry that would fix the input-truncation caps (LLMConstants) for small local models.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Extraction/fit output token budget is derived from the selected model's real output limit, not a fixed 16384
- [ ] #2 Reasoning models no longer fail with invalidJSON due to the output cap being exhausted by thinking tokens
- [ ] #3 Safe fallback for models whose output limit is unknown; Anthropic's required max_tokens is always set to a valid value
- [ ] #4 Unit/integration coverage for the budget derivation
<!-- AC:END -->
