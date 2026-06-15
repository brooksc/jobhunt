---
id: TASK-455
title: >-
  LLM providers: Classify empty successful responses as provider no-response
  errors
status: Done
assignee: []
created_date: '2026-06-13 22:03'
updated_date: '2026-06-15 07:01'
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
modified_files:
  - core/LLM/Providers/OpenAICompatibleTransport.swift
  - core/LLM/Providers/AnthropicProvider.swift
  - core/LLM/Providers/GoogleProvider.swift
  - tests/CoreTests/LLMProviderTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Provider adapters currently convert missing response content into an empty string. OpenAI-compatible, Anthropic, and Google success payloads with no usable model text then fail later as generic JSON parse errors. Empty success responses, blocked candidates, or missing choices/content should be classified at the provider boundary as a no-response or provider-specific unavailable/refusal error.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 OpenAI-compatible transport throws a provider error when a 2xx response contains no usable choice message content.
- [x] #2 Anthropic provider throws a provider error when a 2xx response contains no usable text content block.
- [x] #3 Google provider throws a provider error when a 2xx response contains no usable candidate text, including blocked/empty candidate payloads where applicable.
- [x] #4 Downstream extraction and fit paths preserve the sanitized provider error without leaking raw response bodies.
- [x] #5 Focused provider tests cover empty/missing content for OpenAI-compatible, Anthropic, and Google responses.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
All three provider adapters now throw LLMProviderError.noResponse at the boundary when a 2xx response yields no usable model text (content trimmed to empty), instead of returning "" that failed downstream as a generic JSON parse error: OpenAICompatibleTransport on an empty/missing choice message content (AC#1), AnthropicProvider on no usable text content block (AC#2), GoogleProvider on missing/blocked/empty candidate text (AC#3). noResponse is a clean sanitized error carrying no raw response body, so extraction/fit error persistence doesn't leak provider bodies (AC#4). Added testEmptyContentThrowsNoResponse (OpenAI), testEmptyContentThrowsNoResponse (Anthropic, empty content array), and testEmptyCandidateThrowsNoResponse (Google, empty candidates) (AC#5).
<!-- SECTION:FINAL_SUMMARY:END -->
