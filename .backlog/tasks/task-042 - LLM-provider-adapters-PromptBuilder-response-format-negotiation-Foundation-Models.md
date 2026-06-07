---
id: TASK-042
title: >-
  LLM provider adapters + PromptBuilder + response-format negotiation +
  Foundation Models
status: To Do
assignee: []
created_date: '2026-06-07 22:46'
labels:
  - swift-rewrite
  - core
  - llm
milestone: m-1
dependencies:
  - TASK-035
  - TASK-037
documentation:
  - swift-plan.md
  - server/extract.js
  - server/apple-foundation.js
  - native/foundation-models/main.swift
  - tests/unit/apple-foundation.test.js
priority: high
ordinal: 1900
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: Port the multi-provider LLM transport layer and prompt construction — everything needed to send a chat/extraction request and get text back, for all 7 providers. (The queue, retry, and orchestration live in the ExtractionEngine task; THIS task owns providers + prompts + format negotiation.)

## Read first
- swift-plan.md §8.1 (provider abstraction + concurrency limits), §8.2 (format negotiation ladder), §8.3 (prompt building + char/token budgets), §8.8 (Foundation Models native, macOS 26+), §3 (URLSession/Codable).
- Legacy server/extract.js — postChatCompletion and per-provider dispatch: LM Studio/OpenAI-compatible (/v1/chat/completions), Anthropic Messages API, Google generateContent + JSON mode, OpenRouter (+ free-model rotation query), Custom; the JSON schema (strict) → json_object → prompt-only fallback ladder; system/user prompt construction for extraction and fit scoring.
- Legacy server/apple-foundation.js + native/foundation-models/main.swift — the on-device model usage (LanguageModelSession(instructions:).respond(to:)). REPLACE the subprocess: call FoundationModels directly in-process.
- tests/unit/apple-foundation.test.js, tests/integration/cost.test.js (token/char accounting touchpoints).

## Implement (core/LLM/Providers/ + core/LLM/PromptBuilder.swift)
- `protocol LLMProvider { func complete(_:) async throws -> ChatResponse; var concurrencyLimit: Int }` per §8.1. Adapters: LMStudio, OpenAI, Anthropic, Google, OpenRouter, CustomOpenAI, FoundationModels. Concurrency limits: openai/google/openrouter 3, anthropic 2, apple 1, others 2.
- Response-format negotiation ladder (schema→json_object→prompt-only), recording the response_format used per call.
- `PromptBuilder`: extraction prompts (job description + location prefs + optional resume summary) and fit-score prompts (5-dimension rubric). Honor MAX_DESCRIPTION_CHARS/MAX_RESUME_CHARS and overhead budgeting (§8.3).
- `FoundationModelsProvider` gated `if #available(macOS 26, *)`; availability check used by Settings/Onboarding. Delete reliance on the subprocess.
- Provider selection from SettingsStore (provider + model + base_url + Keychain key).
- OpenRouter free-model rotation pool query (hourly refresh, round-robin) — the pool fetch + selection (the engine drives actual rotation timing).

## Dependencies
Depends on task-035 (settings/Keychain) and task-037 (char limits/normalization constants). Consumed by ExtractionEngine and Settings (test-LLM/model fetch).

## Tests (CoreTests)
- Each adapter builds the correct request (URL/headers/body) — assert via mocked URLProtocol with recorded provider responses. Format-negotiation fallback path. PromptBuilder output shape + truncation at limits. FoundationModels path behind availability (skip on <26). Port apple-foundation.test.js intent.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 All 7 providers implement LLMProvider with correct request building (LM Studio/OpenAI/Anthropic/Google/OpenRouter/Custom/FoundationModels)
- [ ] #2 Concurrency limits per provider match legacy values
- [ ] #3 Format-negotiation ladder (schema→json_object→prompt-only) works and records response_format
- [ ] #4 PromptBuilder reproduces extraction + fit prompts and honors char/overhead budgets
- [ ] #5 FoundationModelsProvider calls the framework in-process, gated to macOS 26+ (no subprocess)
- [ ] #6 CoreTests cover request building (mocked URLProtocol), fallback path, prompt truncation, and availability gating
<!-- AC:END -->
