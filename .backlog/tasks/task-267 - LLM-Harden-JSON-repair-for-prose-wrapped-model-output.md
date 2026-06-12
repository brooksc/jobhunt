---
id: TASK-267
title: 'LLM: Harden JSON repair for prose-wrapped model output'
status: Done
assignee: []
created_date: '2026-06-12 03:25'
updated_date: '2026-06-12 03:30'
labels:
  - audit
  - llm
  - json
  - reliability
dependencies: []
references:
  - core/Util/JSONRepair.swift
  - tests/CoreTests/JSONRepairTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
JSON repair currently handles fenced JSON and a few syntax repairs, but if a text-mode model prefixes or suffixes prose around a valid JSON object, parsing fails. Add a conservative fallback that extracts the first complete top-level object/array before repair validation.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Responses containing prose before or after a single valid JSON object parse successfully.
- [ ] #2 Malformed or ambiguous multi-object responses still fail with a useful error.
- [ ] #3 JSONRepair tests cover prose-wrapped JSON, fenced JSON, trailing commas, and invalid ambiguous responses.
<!-- AC:END -->
