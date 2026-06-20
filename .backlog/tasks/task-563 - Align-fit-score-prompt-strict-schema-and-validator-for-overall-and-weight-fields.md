---
id: TASK-563
title: >-
  Align fit-score prompt, strict schema, and validator for overall and weight
  fields
status: To Do
assignee: []
created_date: '2026-06-20 00:56'
labels:
  - audit
  - llm
  - fit-scoring
  - structured-output
dependencies: []
references:
  - 'core/LLM/PromptBuilder.swift:237'
  - 'core/LLM/PromptBuilder.swift:248'
  - 'core/LLM/StructuredOutputSchemas.swift:57'
  - 'core/LLM/StructuredOutputSchemas.swift:80'
  - 'core/LLM/StructuredOutputSchemas.swift:87'
  - 'core/Services/FitScorer.swift:90'
modified_files:
  - core/LLM/PromptBuilder.swift
  - core/LLM/StructuredOutputSchemas.swift
  - core/Services/FitScorer.swift
  - tests/CoreTests/StructuredOutputSchemasTests.swift
  - tests/CoreTests/FitScorerTests.swift
  - tests/CoreTests/ExtractionEngineTests.swift
  - tests/Support/MockLLM/MockLLMResponder.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: the fit prompt tells the provider not to provide an overall score (`core/LLM/PromptBuilder.swift:248`) and defines each dimension as `name`, `score`, and `rationale` (`core/LLM/PromptBuilder.swift:237`). The strict fit schema requires top-level `overall` and requires each dimension item to include `weight` (`core/LLM/StructuredOutputSchemas.swift:57`, `core/LLM/StructuredOutputSchemas.swift:80`, `core/LLM/StructuredOutputSchemas.swift:87`). The runtime validator then ignores both `overall` and `weight`, validating only dimension names and scores (`core/Services/FitScorer.swift:90`).

Why important: this is three competing contracts for one LLM response. Strict providers are forced to emit fields the prompt says not to emit, while text/json-object fallback responses can omit `weight` and still pass local validation. That makes provider behavior harder to reason about and increases structured-output failure/retry risk when changing prompts, schemas, or providers.

Suggested implementation: choose a single fit-output contract. Prefer removing top-level `overall` and per-dimension `weight` from the strict schema if the application computes both locally, then update mock responders and tests. Alternatively, if the fields are intentionally required for provider compatibility, update the prompt and validator to require and validate them consistently. Add a regression test that compares the fit prompt contract, `StructuredOutputSchemas.fitScore`, and `FitScorer.validateDimensions` expectations.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The fit prompt, strict schema, mock responder, and `FitScorer.validateDimensions` agree on whether `overall` is provider-supplied or locally computed only.
- [ ] #2 The fit prompt, strict schema, mock responder, and validator agree on whether per-dimension `weight` is required.
- [ ] #3 Strict-schema and fallback/text-mode fit-score tests cover the chosen contract.
<!-- AC:END -->
