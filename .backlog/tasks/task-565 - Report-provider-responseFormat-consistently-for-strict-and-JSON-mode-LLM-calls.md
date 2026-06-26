---
id: TASK-565
title: Report provider responseFormat consistently for strict and JSON-mode LLM calls
status: Done
assignee: []
created_date: '2026-06-20 00:57'
updated_date: '2026-06-26 03:52'
labels:
  - audit
  - llm
  - providers
  - diagnostics
dependencies: []
references:
  - 'core/LLM/Providers/OpenAICompatibleTransport.swift:100'
  - 'core/LLM/Providers/AnthropicProvider.swift:47'
  - 'core/LLM/Providers/AnthropicProvider.swift:98'
  - 'core/LLM/Providers/GoogleProvider.swift:62'
  - 'core/LLM/Providers/GoogleProvider.swift:100'
  - 'core/LLM/QueueActor.swift:603'
  - 'core/LLM/QueueActor.swift:793'
modified_files:
  - core/LLM/Providers/AnthropicProvider.swift
  - core/LLM/Providers/GoogleProvider.swift
  - core/LLM/Providers/OpenAICompatibleTransport.swift
  - tests/CoreTests/LLMProviderTests.swift
  - tests/CoreTests/LLMDynamicModelTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: provider adapters do not report `ChatResponse.responseFormat` consistently with the format actually requested/sent. OpenAI-compatible transports return the format ladder result (`core/LLM/Providers/OpenAICompatibleTransport.swift:100`). Anthropic sends `output_config.format` with a JSON schema but reports `.jsonObject` on success (`core/LLM/Providers/AnthropicProvider.swift:47`, `core/LLM/Providers/AnthropicProvider.swift:98`). Google sends `generationConfig.responseMimeType = application/json` and sometimes `responseSchema`, but always reports `.text` (`core/LLM/Providers/GoogleProvider.swift:62`, `core/LLM/Providers/GoogleProvider.swift:100`). Queue attempt records persist this value as the actual response format (`core/LLM/QueueActor.swift:603`, `core/LLM/QueueActor.swift:793`).

Why important: response-format telemetry is used to diagnose provider capability, fallback behavior, and structured-output reliability. Today the same strict-schema extraction can be recorded as `json_schema`, `json_object`, or `text` depending on provider adapter rather than actual constraint level. That makes the Debug tab/attempt history misleading and obscures whether fallback occurred.

Suggested implementation: define provider-agnostic semantics for `ChatResponse.responseFormat`: e.g. `.jsonSchema` when a schema/responseSchema/output_config schema was successfully used, `.jsonObject` when JSON mode without schema was used, `.text` only for free-form fallback. Update Anthropic and Google adapters to return the selected effective format, including after fallback. Add adapter tests that assert returned responseFormat, not only outbound request shape.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Successful strict-schema calls are recorded with the same responseFormat semantics across OpenAI-compatible, Anthropic, and Google providers.
- [x] #2 JSON-mode fallback without schema records `.jsonObject`; free-form fallback records `.text`.
- [x] #3 Provider tests assert the returned `ChatResponse.responseFormat` for strict success, JSON fallback, and text fallback where supported.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Provider adapters now report ChatResponse.responseFormat by effective constraint level, consistently across providers. Anthropic returns .jsonSchema(name,schema) on a successful structured call (was .jsonObject) and .text after the 400 output_config fallback. Google returns .jsonSchema when the responseSchema was applied, .jsonObject for JSON-mode without schema or after a 400 schema-downgrade, and .text for free-form (was always .text). OpenAI-compatible already reported the ladder result. Tests (LLMProviderTests Anthropic/Google) assert returned responseFormat for strict success, JSON-mode, schema-downgrade→jsonObject, and text; corrected the stale AnthropicStructuredOutputTests assertion that expected jsonObject. Full CoreTests (940) green; lint clean. Commit a677ddb.
<!-- SECTION:FINAL_SUMMARY:END -->
