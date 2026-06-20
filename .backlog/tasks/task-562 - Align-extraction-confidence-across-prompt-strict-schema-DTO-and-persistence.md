---
id: TASK-562
title: 'Align extraction confidence across prompt, strict schema, DTO, and persistence'
status: To Do
assignee: []
created_date: '2026-06-20 00:56'
labels:
  - audit
  - llm
  - extraction
  - structured-output
dependencies: []
references:
  - 'core/LLM/PromptBuilder.swift:112'
  - 'core/LLM/StructuredOutputSchemas.swift:18'
  - 'core/LLM/ExtractionDTO.swift:60'
  - 'core/LLM/ExtractionEngine.swift:150'
modified_files:
  - core/LLM/PromptBuilder.swift
  - core/LLM/StructuredOutputSchemas.swift
  - core/LLM/ExtractionDTO.swift
  - core/LLM/ExtractionEngine.swift
  - tests/CoreTests/StructuredOutputSchemasTests.swift
  - tests/CoreTests/ExtractionDTOTests.swift
  - tests/CoreTests/ExtractionEngineTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: the extraction prompt asks the provider to return `confidence` as one of the exact JSON keys (`core/LLM/PromptBuilder.swift:112`), and `ExtractionEngine.extract` has special handling to preserve raw confidence and compute `extractionConfidence` (`core/LLM/ExtractionEngine.swift:150`). However, the strict `jobExtraction` schema has `additionalProperties: false` and does not include `confidence` in `properties` or `required` (`core/LLM/StructuredOutputSchemas.swift:18`). `ExtractionDTO` also documents that confidence is outside the strict schema (`core/LLM/ExtractionDTO.swift:60`). With strict structured-output providers, the model is forbidden from returning the field that the prompt and persistence path expect.

Why important: extraction confidence becomes provider/format-dependent. A text/json-object fallback can return confidence, but strict json_schema providers are steered away from it, so `job.extractionConfidence` can be systematically nil despite the prompt claiming confidence is part of the contract. That undermines provenance and makes provider comparisons misleading.

Suggested implementation: make one contract authoritative. Either add `confidence` to `StructuredOutputSchemas.jobExtraction` and `ExtractionDTO`, with tests proving it survives strict-schema extraction, or remove confidence from the prompt and stop treating it as expected output. Prefer adding it if confidence is still user-visible/valuable. Add a schema-vs-prompt regression test that checks every prompt-listed extraction key is represented in the schema/DTO boundary.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The extraction prompt, strict schema, DTO, and persisted `extractionConfidence` behavior agree on whether `confidence` is part of the output contract.
- [ ] #2 Strict-schema extraction tests prove confidence is either preserved intentionally or no longer requested/expected.
- [ ] #3 A regression test prevents prompt-listed extraction keys from drifting away from schema/DTO keys.
<!-- AC:END -->
