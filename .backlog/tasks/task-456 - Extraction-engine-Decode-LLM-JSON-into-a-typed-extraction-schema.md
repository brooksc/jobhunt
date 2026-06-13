---
id: TASK-456
title: 'Extraction engine: Decode LLM JSON into a typed extraction schema'
status: To Do
assignee: []
created_date: '2026-06-13 22:03'
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
- [ ] #1 Repaired extraction JSON is decoded into a typed DTO that represents the expected extraction schema.
- [ ] #2 Invalid or incompatible field shapes produce a clear invalid-response error rather than silent field loss where the field is required by the schema contract.
- [ ] #3 Permitted coercions are explicit and tested, such as numeric strings if the product intentionally supports them.
- [ ] #4 Existing normalization behavior for salary, company, location, and remote type still runs after typed decoding.
- [ ] #5 Focused tests cover valid extraction JSON, malformed field types, missing optional fields, and any supported coercions.
<!-- AC:END -->
