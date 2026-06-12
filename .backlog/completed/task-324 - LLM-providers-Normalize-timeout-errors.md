---
id: TASK-324
title: 'LLM providers: Normalize timeout errors'
status: Done
assignee: []
created_date: '2026-06-12 20:02'
updated_date: '2026-06-12 20:18'
labels:
  - audit
  - llm-provider
  - errors
dependencies: []
references:
  - core/LLM/LLMProvider.swift
  - core/LLM/Providers/OpenAICompatibleTransport.swift
  - core/LLM/Providers/GoogleProvider.swift
  - core/LLM/Providers/AnthropicProvider.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
LLMProviderError.timeout exists, but provider transports let URLSession timeout errors bubble directly. Queue-visible errors can vary by provider/platform instead of using the sanitized timeout message.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Provider transports catch URLError.timedOut and map it to LLMProviderError.timeout with the configured timeout seconds.
- [ ] #2 Queue history persists sanitized timeout messages consistently across providers.
- [ ] #3 Tests cover timeout mapping for OpenAI-compatible and provider-specific transports.
<!-- AC:END -->
