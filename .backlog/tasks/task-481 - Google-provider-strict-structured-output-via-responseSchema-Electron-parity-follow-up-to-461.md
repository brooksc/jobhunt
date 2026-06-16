---
id: TASK-481
title: >-
  Google provider: strict structured output via responseSchema (Electron parity
  follow-up to 461)
status: To Do
assignee: []
created_date: '2026-06-16 23:32'
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
- [ ] #1 GoogleProvider sends generationConfig.responseSchema (Gemini dialect) when a structured-output kind / .jsonSchema response format is requested
- [ ] #2 The Gemini schema is derived from StructuredOutputSchemas without unsupported keywords (e.g. additionalProperties) that Gemini rejects
- [ ] #3 Falls back gracefully (responseMimeType JSON only, or text) if Gemini rejects the responseSchema
- [ ] #4 Verified with LLMEval against a real Gemini key for field completeness
<!-- AC:END -->
