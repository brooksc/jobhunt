---
id: TASK-037
title: >-
  Extraction field normalization: salary, remote type, location, company
  inference
status: To Do
assignee: []
created_date: '2026-06-07 22:44'
labels:
  - swift-rewrite
  - core
  - llm
milestone: m-1
dependencies:
  - TASK-033
documentation:
  - swift-plan.md
  - server/extract.js
  - static/transform.js
  - tests/unit/extract.test.js
  - tests/unit/transform.test.js
priority: high
ordinal: 1400
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: Port the post-LLM normalization logic that turns raw extracted JSON into clean, filterable fields. Pure functions, no SwiftData — the highest-value unit-tested logic in the backend.

## Read first
- swift-plan.md §8.4 (parsing & normalization), §8.3 (char limits), §10.2 (fields shown).
- Legacy server/extract.js — the normalization helpers specifically: salary mining (bands, hourly→annual conversion, currency detection), remote-type inference (URL params for LinkedIn/Indeed/Levels.fyi + description heuristics), location inference ("based in"/title-context patterns), company backfill from structured data. Read these functions carefully and reproduce exactly.
- static/transform.js (mapStatus/mapRemote/mapEmployment/mapExtractionStatus) — the display-normalization rules.

## Implement (core/LLM/Normalization.swift or core/Services/)
- `SalaryNormalizer` (min/max/currency/note from text + extracted JSON; hourly→annual; band parsing).
- `RemoteTypeInferer` (URL param signals + description heuristics → remote/hybrid/onsite).
- `LocationInferer` and `CompanyBackfiller`.
- A `JobFieldNormalizer` that composes them: takes raw extracted dict + source capture context → normalized Job field values.
- Mirror the MAX_DESCRIPTION_CHARS (32000) / MAX_RESUME_CHARS (12000) constants here or in a shared Constants file.

## Dependencies
Depends on task-033. Independent of models (operates on dicts/strings). Consumed by the ExtractionEngine (M).

## Tests (CoreTests) — port existing
- Port tests/unit/extract.test.js, tests/unit/transform.test.js (and any salary/remote fixtures) to XCTest, asserting identical normalized outputs. Cover hourly→annual, currency detection, LinkedIn/Indeed/Levels URL signals, and title-based location inference.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Salary normalization matches extract.js (bands, hourly→annual, currency) on shared fixtures
- [ ] #2 Remote-type inference reproduces URL-param + heuristic results for LinkedIn/Indeed/Levels
- [ ] #3 Location inference and company backfill match legacy behavior
- [ ] #4 JobFieldNormalizer composes the pieces into normalized Job fields
- [ ] #5 Ported extract.test.js + transform.test.js pass as XCTest; module imports no SwiftData/SwiftUI
<!-- AC:END -->
