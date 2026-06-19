---
id: TASK-539
title: 'LLM: map Anthropic 429 responses to typed rate-limit errors'
status: To Do
assignee: []
created_date: '2026-06-19 04:57'
labels:
  - audit
  - llm
  - anthropic
  - rate-limit
  - retry
dependencies: []
references:
  - core/LLM/Providers/AnthropicProvider.swift
  - core/LLM/LLMProvider.swift
  - core/LLM/QueueActor.swift
  - tests/CoreTests/LLMProviderTests.swift
  - tests/CoreTests/RetryAfterParserTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: the shared OpenAI-compatible transport and Google provider map HTTP 429 to `LLMProviderError.rateLimited(retryAfter:)`, allowing `QueueActor` to honor Retry-After, reduce adaptive concurrency, and avoid counting rate limits toward auto-pause. `AnthropicProvider.send(...)` currently treats every non-2xx response as `LLMProviderError.httpError`, including 429.

Why this matters: this makes retry behavior provider-dependent in a way the queue abstraction is supposed to hide. Anthropic rate limits can increment the provider-failure streak, contribute to auto-pause, and use generic exponential backoff instead of the provider-advised wait. That is a reliability and cost-control issue for cloud LLM usage.

Suggested implementation: handle `http.statusCode == 429` in `AnthropicProvider.send(...)` before the generic non-2xx path, parse `Retry-After` and any body hints through `RetryAfterParser`, and throw `.rateLimited(retryAfter:)`. Add provider tests mirroring the OpenAI-compatible/Google 429 behavior, including header-based Retry-After and sanitized error persistence through the queue where appropriate.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Anthropic HTTP 429 responses throw `LLMProviderError.rateLimited` instead of generic `httpError`.
- [ ] #2 The Anthropic path parses `Retry-After` headers with the shared `RetryAfterParser`.
- [ ] #3 Queue handling for Anthropic 429s reduces adaptive concurrency and does not increment the provider-failure auto-pause streak.
- [ ] #4 Tests cover Anthropic 429 with and without Retry-After metadata.
- [ ] #5 Existing Anthropic non-429 HTTP errors continue to throw sanitized `httpError` descriptions.
- [ ] #6 The behavior remains consistent with TASK-463's provider-agnostic rate-limit contract.
<!-- AC:END -->
