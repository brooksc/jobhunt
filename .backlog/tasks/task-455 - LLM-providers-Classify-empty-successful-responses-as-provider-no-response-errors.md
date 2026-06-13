---
id: TASK-455
title: >-
  LLM providers: Classify empty successful responses as provider no-response
  errors
status: To Do
assignee: []
created_date: '2026-06-13 22:03'
labels:
  - bug
  - llm
  - providers
dependencies: []
references:
  - core/LLM/Providers/OpenAICompatibleTransport.swift
  - core/LLM/Providers/AnthropicProvider.swift
  - core/LLM/Providers/GoogleProvider.swift
  - core/LLM/LLMProvider.swift
  - tests/CoreTests/LLMProviderTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Provider adapters currently convert missing response content into an empty string. OpenAI-compatible, Anthropic, and Google success payloads with no usable model text then fail later as generic JSON parse errors. Empty success responses, blocked candidates, or missing choices/content should be classified at the provider boundary as a no-response or provider-specific unavailable/refusal error.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 OpenAI-compatible transport throws a provider error when a 2xx response contains no usable choice message content.
- [ ] #2 Anthropic provider throws a provider error when a 2xx response contains no usable text content block.
- [ ] #3 Google provider throws a provider error when a 2xx response contains no usable candidate text, including blocked/empty candidate payloads where applicable.
- [ ] #4 Downstream extraction and fit paths preserve the sanitized provider error without leaking raw response bodies.
- [ ] #5 Focused provider tests cover empty/missing content for OpenAI-compatible, Anthropic, and Google responses.
<!-- AC:END -->
