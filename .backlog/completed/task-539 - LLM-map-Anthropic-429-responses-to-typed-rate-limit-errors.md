---
id: TASK-539
title: 'LLM: map Anthropic 429 responses to typed rate-limit errors'
status: Done
assignee: []
created_date: '2026-06-19 04:57'
updated_date: '2026-06-26 04:08'
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
- [x] #1 Anthropic HTTP 429 responses throw `LLMProviderError.rateLimited` instead of generic `httpError`.
- [x] #2 The Anthropic path parses `Retry-After` headers with the shared `RetryAfterParser`.
- [x] #3 Queue handling for Anthropic 429s reduces adaptive concurrency and does not increment the provider-failure auto-pause streak.
- [x] #4 Tests cover Anthropic 429 with and without Retry-After metadata.
- [x] #5 Existing Anthropic non-429 HTTP errors continue to throw sanitized `httpError` descriptions.
- [x] #6 The behavior remains consistent with TASK-463's provider-agnostic rate-limit contract.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
AnthropicProvider.send now handles http.statusCode == 429 before the generic non-2xx guard: it parses Retry-After via the shared RetryAfterParser.parse(header:body:now:) and throws LLMProviderError.rateLimited(retryAfter:), identical to the OpenAI-compatible and Google paths (TASK-463 contract). The queue therefore honors the advised wait, reduces adaptive concurrency, and doesn't count Anthropic 429s toward the provider-failure auto-pause streak. Non-429 errors still throw sanitized httpError, and the 400 output_config structured-output fallback is unaffected (it matches httpError(400), not rateLimited). Tests: test429WithRetryAfterThrowsRateLimited (retryAfter == 30) and test429WithoutRetryAfterStillThrowsRateLimited. Lint clean; AnthropicProviderTests pass.
<!-- SECTION:FINAL_SUMMARY:END -->
