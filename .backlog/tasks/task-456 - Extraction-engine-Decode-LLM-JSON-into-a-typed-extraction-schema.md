---
id: TASK-456
title: 'Extraction engine: Decode LLM JSON into a typed extraction schema'
status: Done
assignee: []
created_date: '2026-06-13 22:03'
updated_date: '2026-06-15 19:05'
labels:
  - llm
  - extraction
  - maintainability
dependencies: []
references:
  - core/LLM/ExtractionEngine.swift
  - core/LLM/Normalization.swift
  - tests/CoreTests/ExtractionEngineTests.swift
  - tests/CoreTests/NormalizationTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Extraction currently keeps repaired provider JSON as `[String: Any?]` until the final `ExtractionResult`, then casts values directly into app fields. Provider drift in salary, employment type, arrays, confidence, or URLs can silently drop fields or persist partial results. The extraction boundary should decode into an explicit typed schema with validation and controlled coercion before normalization and persistence.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Repaired extraction JSON is decoded into a typed DTO that represents the expected extraction schema.
- [x] #2 Invalid or incompatible field shapes produce a clear invalid-response error rather than silent field loss where the field is required by the schema contract.
- [x] #3 Permitted coercions are explicit and tested, such as numeric strings if the product intentionally supports them.
- [x] #4 Existing normalization behavior for salary, company, location, and remote type still runs after typed decoding.
- [x] #5 Focused tests cover valid extraction JSON, malformed field types, missing optional fields, and any supported coercions.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added `ExtractionDTO` (core/LLM/ExtractionDTO.swift): a validating typed decode of the parsed provider JSON into the documented extraction schema, run in `ExtractionEngine.extract` before normalization. Incompatible field shapes throw the new `ExtractionEngineError.malformedField` (retryable) instead of silent field loss. Explicit/tested coercions: integer fields accept an integral number or numeric string (floats round); number fields accept any number or numeric string; array fields tolerate missing/null (→ empty) and skip non-string elements; booleans in numeric fields are rejected. The DTO rebuilds the snake_case dict the SalaryNormalizer/CompanyBackfiller/LocationInferer/RemoteTypeInferer passes consume, so normalization behavior is unchanged (verified by existing extract() normalization tests + a new remote-inference-after-decode test); `confidence` (outside the strict schema) is preserved verbatim. Tests: ExtractionDTOTests (valid, missing/null, numeric-string & float coercion, element-dropping, malformed object/string/array/bool shapes, snake_case round-trip) + two extract() integration tests. Full fast gate (725 CoreTests) green; app builds. Minor: extra keys outside the schema are dropped from stored extractedJSON — a no-op for additionalProperties:false-compliant providers.
<!-- SECTION:FINAL_SUMMARY:END -->
