---
id: TASK-036
title: 'Core text utilities: Cleaning, JD block parser, JSON repair, Metros'
status: Done
assignee:
  - claude
created_date: '2026-06-07 22:44'
updated_date: '2026-06-08 02:13'
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
- [x] #1 Cleaning reproduces cleaning.js output for the same inputs (selected/visible preference, JSON-LD, HTML strip, Workday band split)
- [x] #2 JDParser reproduces static/jd-parser.js block output including boilerplate skip and LinkedIn dup-marker stop
- [x] #3 JSONRepair recovers fenced/trailing-comma/unquoted-key/single-quote malformed JSON
- [x] #4 Metros tables + parsePreferredMetros + expandMetros match metros.js
- [x] #5 Ported XCTest versions of cleaning + jd-parser JS tests pass; utilities import no SwiftData/SwiftUI
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Implemented four pure-Foundation Swift utilities in core/Util/:

- **Cleaning.swift**: Ports cleanDescription (selectedText preference, JSON-LD @graph traversal, HTML stripping with entity decode, Workday salary-band newline splitting), normalizeWhitespace, and stripHtml. Function-for-function match with server/cleaning.js.

- **JDParser.swift**: Ports parseJdBlocks returning [JDBlock] enum (heading/paragraph/list/hr). Handles boilerplate skipping (30-line lookahead for prose/header/emoji), LinkedIn "Feed post" chrome skip, LinkedIn concatenated duplicate stop, trailing hr removal. Mirrors static/jd-parser.js.

- **JSONRepair.swift**: Implements extractJSON (strips ```json fences), repairJSON (trailing commas, unquoted keys, single-quote conversion, fenced blocks). Validates output with JSONSerialization.

- **Metros.swift**: Full METRO_DATA table (20 states), parsePreferredMetros, expandMetros with deduplication and state abbreviation/full-name inclusion. Exact mirror of server/metros.js.

Tests in Tests/CoreTests/: CleaningTests.swift (15 tests porting cleaning.test.js), JDParserTests.swift (12 tests porting jd-parser.test.js with inline LinkedIn fixture), JSONRepairTests.swift (11 tests), MetrosTests.swift (14 tests). All 100 CoreTests pass. No SwiftUI/AppKit/SwiftData imports in any utility file.
<!-- SECTION:FINAL_SUMMARY:END -->
