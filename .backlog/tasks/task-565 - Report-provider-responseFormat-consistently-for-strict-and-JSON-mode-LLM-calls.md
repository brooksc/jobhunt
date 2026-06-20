---
id: TASK-565
title: Report provider responseFormat consistently for strict and JSON-mode LLM calls
status: To Do
assignee: []
created_date: '2026-06-20 00:57'
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
- [ ] #1 Successful strict-schema calls are recorded with the same responseFormat semantics across OpenAI-compatible, Anthropic, and Google providers.
- [ ] #2 JSON-mode fallback without schema records `.jsonObject`; free-form fallback records `.text`.
- [ ] #3 Provider tests assert the returned `ChatResponse.responseFormat` for strict success, JSON fallback, and text fallback where supported.
<!-- AC:END -->
