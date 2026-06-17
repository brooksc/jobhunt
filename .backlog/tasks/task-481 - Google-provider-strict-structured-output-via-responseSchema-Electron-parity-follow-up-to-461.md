---
id: TASK-481
title: >-
  Google provider: strict structured output via responseSchema (Electron parity
  follow-up to 461)
status: Done
assignee: []
created_date: '2026-06-16 23:32'
updated_date: '2026-06-17 05:22'
labels:
  - llm
  - provider
  - electron-parity
  - google
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up scoped out of TASK-461. TASK-461 enabled strict `json_schema` structured output for OpenAI-compatible providers (and Anthropic already enforces the schema via `structuredOutput`). `GoogleProvider` currently maps both `.jsonObject` and `.jsonSchema` to `generationConfig.responseMimeType: "application/json"` (JSON mode) but does NOT send a strict schema.

To reach parity, Gemini supports `generationConfig.responseSchema` (a JSON-Schema-like object, with some unsupported keywords vs OpenAI) + `responseMimeType: "application/json"`. Wire `StructuredOutputSchemas.schema(for:)` into GoogleProvider's `generationConfig.responseSchema` when `request.structuredOutput`/`.jsonSchema` is present, accounting for Gemini's schema dialect differences (no `additionalProperties`, enum/format support differs).

References: core/LLM/Providers/GoogleProvider.swift, core/LLM/StructuredOutputSchemas.swift
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 GoogleProvider sends generationConfig.responseSchema (Gemini dialect) when a structured-output kind / .jsonSchema response format is requested
- [x] #2 The Gemini schema is derived from StructuredOutputSchemas without unsupported keywords (e.g. additionalProperties) that Gemini rejects
- [x] #3 Falls back gracefully (responseMimeType JSON only, or text) if Gemini rejects the responseSchema
- [ ] #4 Verified with LLMEval against a real Gemini key for field completeness
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
GoogleProvider now reaches structured-output parity with the OpenAI `json_schema` / Anthropic `structuredOutput` paths.

**Implementation (`core/LLM/Providers/GoogleProvider.swift`):**
- `geminiResponseSchema(fromJSONSchema:)` converts a `StructuredOutputSchemas` JSON Schema string into Gemini's OpenAPI-3.0 `responseSchema` dialect — drops `additionalProperties` (Gemini rejects it) and `$schema`, rewrites `["x","null"]` unions as `type: X` + `nullable: true`, uppercases types to the `Type` enum (STRING/INTEGER/NUMBER/BOOLEAN/ARRAY/OBJECT), recursing through `properties` and `items` (AC#1, AC#2).
- For `.jsonSchema` it sends `generationConfig.responseSchema` alongside `responseMimeType: application/json`; `.jsonObject` stays JSON-mode-only (AC#1).
- **Graceful fallback (AC#3):** if Gemini returns HTTP 400 on the schema-bearing request, it retries once in plain JSON mode (no `responseSchema`), degrading to the pre-481 behavior — the prompt already states the field contract. Extracted the existing 429 retry/timeout handling into a private `send(_:to:)` shared by both attempts.

**Tests (`tests/CoreTests/LLMProviderTests.swift`, GoogleProviderTests, all green):** dialect transform, recursion into array items, invalid-JSON→nil, `.jsonSchema` sends responseSchema, `.jsonObject` omits it, 400→single-retry-without-schema, and a non-schema 400 does NOT retry. Full GoogleProviderTests suite: 15 tests, 0 failures.

**AC#4 (verify with LLMEval against a real Gemini key) — PENDING:** no Gemini API key is available in this environment, so end-to-end field-completeness against the live API hasn't been run. Left unchecked. The 400-fallback (AC#3) makes the change safe to ship even if Gemini's schema dialect needs further tweaks: a rejected schema can't fail extraction, only forgo the strict-schema enforcement for that call. Recommend a single live extraction run against a Gemini key to confirm the schema is accepted (not silently 400-falling-back every time) and that field completeness improves — same live-verify follow-up posture as TASK-461/462/463.
<!-- SECTION:FINAL_SUMMARY:END -->
