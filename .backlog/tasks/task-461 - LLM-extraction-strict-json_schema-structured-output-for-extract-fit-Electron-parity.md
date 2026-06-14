---
id: TASK-461
title: >-
  LLM extraction: strict json_schema structured output for extract + fit
  (Electron parity)
status: To Do
assignee: []
created_date: '2026-06-14 04:39'
labels:
  - llm
  - provider
  - electron-parity
  - phase-5
  - extraction
dependencies: []
references:
  - core/LLM/ExtractionEngine.swift
  - core/LLM/Providers/OpenAICompatibleTransport.swift
  - core/LLM/LLMProvider.swift
  - core/LLM/PromptBuilder.swift
  - core/Services/FitScorer.swift
  - core/LLM/Providers/GoogleProvider.swift
  - tests/CoreTests/ExtractionEngineTests.swift
  - server/extract.js@8c438ca (extractedJobSchema/fitScoreSchema/FIT_DIMENSIONS)
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Context
The OpenAI-compatible transport ALREADY supports a `json_schema → json_object → text` negotiation ladder with `strict: true` and graceful HTTP-400 fallback — see `OpenAICompatibleTransport.responseFormatJSON` (OpenAICompatibleTransport.swift:123-141) and the ladder (OpenAICompatibleTransport.swift:32-41, falls to the next format on a 400 whose body mentions `response_format`/`json_schema`/`json_object`). The `ResponseFormat.jsonSchema(name:schema:)` case exists (LLMProvider.swift:17-21).

BUT no caller ever builds a schema. Extraction sends `responseFormat: .jsonObject` (ExtractionEngine.swift:121) and fit sends `.jsonObject` (ExtractionEngine.swift:206). Electron's `server/extract.js` sent `response_format:{type:'json_schema',strict:true,schema: extractedJobSchema()/fitScoreSchema()}` as the FIRST ladder rung (enforcing remote_type enum, dimensions minItems/maxItems, etc.). Dropped in the Swift port, so correctness now relies entirely on the prompt + jsonrepair.

## What to change (how)
1. Author two JSON Schema string constants (new file `core/LLM/ExtractionSchemas.swift`): `extractedJobSchema` and `fitScoreSchema`. Port the exact shapes from Electron: `git show 8c438ca:server/extract.js` → search `extractedJobSchema`, `fitScoreSchema`, `FIT_DIMENSIONS`, `FIT_DIMENSION_WEIGHTS`.
2. Pass them from ExtractionEngine: line 121 → `.jsonSchema(name: "extracted_job", schema: extractedJobSchema)`; line 206 (fit) → `.jsonSchema(name: "fit_score", schema: fitScoreSchema)`. No transport change needed (the ladder already handles fallback).

## Hard design constraints (get these right or it degrades extraction)
- OpenAI `strict:true` requires `additionalProperties:false` AND every property listed in `required` for every object. Use nullable types (`"type":["string","null"]`) for optional fields and mark them required — that is OpenAI's strict-mode idiom.
- The schema must NOT be stricter than what `JobFieldNormalizer` + `Projections.JobDetailProjection` + `FitScorer.rescoreFromJSON` tolerate. Keep enums permissive (or omit them and let the normalizer map values).
- Fit schema: require a `dimensions` array of the 5 FIT_DIMENSIONS objects (`{name, score}`), plus `requirements_met`/`requirements_not_met` arrays — `FitScorer.rescoreFromJSON` reads `dimensions:[{name,score}]` and `requirements_not_met`.

## Important: Google is separate
`GoogleProvider` does NOT use `OpenAICompatibleTransport`. Gemini structured output uses `generationConfig.responseSchema` + `responseMimeType:"application/json"` (a different shape). Either implement it there too, or explicitly scope this task to OpenAI-compatible providers and file Google separately.

## Risk / verification (cannot be build-verified)
This changes the wire format for providers that ACCEPT json_schema. A wrong schema constrains the model incorrectly → worse extraction; the 400-fallback only triggers on REJECTION, not on an accepted-but-wrong schema. MUST be verified with the `LLMEval` target against a real OpenAI key: run extraction + fit on the reference JDs in `tests/fixtures` and compare field completeness with json_schema ON vs the prior json_object path.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 extractedJobSchema and fitScoreSchema string constants exist (e.g. core/LLM/ExtractionSchemas.swift) and a unit test confirms JSONSerialization can parse each as valid JSON
- [ ] #2 ExtractionEngine extraction (line ~121) and fit (line ~206) pass .jsonSchema(name:schema:) instead of .jsonObject
- [ ] #3 Schema shapes are compatible with JobFieldNormalizer and FitScorer.rescoreFromJSON (no field the parser needs is excluded; fit dimensions array matches the 5 FIT_DIMENSIONS)
- [ ] #4 On a provider that rejects json_schema (HTTP 400 format error) the transport ladder falls back to json_object then text without failing extraction (confirm via a transport unit test)
- [ ] #5 Google structured output is either implemented via responseSchema/responseMimeType OR this task is explicitly scoped to OpenAI-compatible providers with a separate Google follow-up filed
- [ ] #6 LLMEval with a real cloud key shows equal-or-better field completeness vs json_object on the reference JDs, with no schema-rejection loops
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 Verified with the LLMEval target against at least one real cloud provider API key; before/after field-completeness documented in the task notes
- [ ] #2 json_schema -> json_object -> text fallback confirmed working for a provider that rejects the schema
<!-- DOD:END -->
