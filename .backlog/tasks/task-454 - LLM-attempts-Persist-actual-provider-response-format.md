---
id: TASK-454
title: 'LLM attempts: Persist actual provider response format'
status: Done
assignee: []
created_date: '2026-06-13 22:03'
updated_date: '2026-06-15 19:00'
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
- [x] #1 Extraction and fit engine outputs expose the actual `ChatResponse.responseFormat` returned by the provider.
- [x] #2 Successful extraction and fit `LLMRequestAttempt` rows persist the actual response format instead of a hardcoded value.
- [x] #3 Response-format downgrade through OpenAI-compatible transport is reflected in attempt history.
- [x] #4 Focused tests cover JSON-object success, text fallback/downgrade, and providers that always return text.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ExtractionResult and FitScoreOutput now expose the actual ChatResponse.responseFormat the provider used. QueueActor persists its `.wireValue` (json_schema/json_object/text) on both the extraction and fit success `LLMRequestAttempt` rows — replacing the hardcoded "json_object" for fit and the previously-nil extraction value. Added `ResponseFormat.wireValue`. A provider downgrade (OpenAICompatibleTransport returns the negotiated format in ChatResponse) now flows through to attempt history. Tests: engine surfaces json_object/text for both extraction and fit, an always-text provider, and the persisted fit attempt records the provider's actual format. Fast gate green; app builds.
<!-- SECTION:FINAL_SUMMARY:END -->
