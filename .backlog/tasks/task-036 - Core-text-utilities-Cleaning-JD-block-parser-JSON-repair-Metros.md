---
id: TASK-036
title: 'Core text utilities: Cleaning, JD block parser, JSON repair, Metros'
status: In Progress
assignee:
  - claude
created_date: '2026-06-07 22:44'
updated_date: '2026-06-08 02:05'
labels:
  - swift-rewrite
  - core
  - util
milestone: m-1
dependencies:
  - TASK-033
documentation:
  - swift-plan.md
  - server/cleaning.js
  - static/jd-parser.js
  - server/metros.js
  - tests/unit/cleaning.test.js
  - tests/unit/jd-parser.test.js
priority: high
ordinal: 1300
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: Port the pure, dependency-free text/parsing utilities used across extraction, capture cleaning, the Detail raw-text view, and location handling. All are pure functions — heavily unit-testable, no SwiftData needed.

## Read first
- swift-plan.md §9 (Cleaning, Metros), §10.2 (Detail Raw tab uses JD parser), §8.4 (JSON repair), §3 (jsonrepair port note).
- Legacy sources to port behavior from, function-for-function:
  - server/cleaning.js → text cleaning (selected vs visible text preference, JSON-LD JobPosting extraction, HTML strip/entity decode, Workday salary-band newline splitting).
  - static/jd-parser.js → parseJdBlocks (headings/paragraphs/lists/hr; boilerplate skipping; LinkedIn dup marker stop).
  - server/metros.js → metro/city tables, parsePreferredMetros, expandMetros.
  - The npm `jsonrepair` behavior → a Swift JSONRepair that recovers malformed LLM JSON (unquoted keys, trailing commas, fenced ```json blocks, single quotes). Port the essentials; doesn't need 100% of the library.

## Implement (core/Util/)
- `Cleaning` (cleanDescription + JSON-LD helpers), `JDParser` (parseJdBlocks → [JDBlock] enum), `JSONRepair` (repair(String) -> String + extractJSON to strip markdown fences), `Metros` (tables + parse/expand).
- Keep these free of SwiftData/SwiftUI imports so they live in the lowest Core layer.

## Dependencies
Depends on task-033 (scaffold). No model dependency. Used by extraction (E/M), dedup (F), JobService (N), and the Detail screen (T).

## Tests (CoreTests) — port the existing JS tests directly
- Port tests/unit/cleaning.test.js, tests/unit/jd-parser.test.js, and any metros coverage to XCTest with the same fixtures/assertions. Add JSONRepair tests covering fenced blocks, trailing commas, unquoted keys, single quotes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Cleaning reproduces cleaning.js output for the same inputs (selected/visible preference, JSON-LD, HTML strip, Workday band split)
- [ ] #2 JDParser reproduces static/jd-parser.js block output including boilerplate skip and LinkedIn dup-marker stop
- [ ] #3 JSONRepair recovers fenced/trailing-comma/unquoted-key/single-quote malformed JSON
- [ ] #4 Metros tables + parsePreferredMetros + expandMetros match metros.js
- [ ] #5 Ported XCTest versions of cleaning + jd-parser JS tests pass; utilities import no SwiftData/SwiftUI
<!-- AC:END -->
