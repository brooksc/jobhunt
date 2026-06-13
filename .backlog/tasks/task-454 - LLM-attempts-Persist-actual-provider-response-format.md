---
id: TASK-454
title: 'LLM attempts: Persist actual provider response format'
status: To Do
assignee: []
created_date: '2026-06-13 22:03'
labels:
  - llm
  - observability
  - queue
dependencies: []
references:
  - core/LLM/LLMProvider.swift
  - core/LLM/ExtractionEngine.swift
  - core/LLM/QueueActor.swift
  - tests/CoreTests/ExtractionEngineTests.swift
  - tests/CoreTests/LLMProviderTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`ChatResponse` records the actual response format used by the provider, but extraction and fit outputs drop that metadata. Fit attempts currently hardcode `responseFormat` as `json_object`, even when a provider always returns text or an OpenAI-compatible provider downgrades from JSON mode to text. Attempt history should reflect the actual provider response mode for debugging JSON failures and provider reliability.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Extraction and fit engine outputs expose the actual `ChatResponse.responseFormat` returned by the provider.
- [ ] #2 Successful extraction and fit `LLMRequestAttempt` rows persist the actual response format instead of a hardcoded value.
- [ ] #3 Response-format downgrade through OpenAI-compatible transport is reflected in attempt history.
- [ ] #4 Focused tests cover JSON-object success, text fallback/downgrade, and providers that always return text.
<!-- AC:END -->
