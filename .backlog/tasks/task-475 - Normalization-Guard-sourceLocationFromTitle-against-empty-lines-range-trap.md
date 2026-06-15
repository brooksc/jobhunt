---
id: TASK-475
title: 'Normalization: Guard sourceLocationFromTitle against empty lines range trap'
status: Done
assignee: []
created_date: '2026-06-15 03:39'
updated_date: '2026-06-15 07:05'
labels:
  - bug
  - core
  - llm
dependencies: []
references:
  - core/LLM/Normalization.swift
modified_files:
  - core/LLM/Normalization.swift
  - tests/CoreTests/NormalizationTests.swift
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`LocationInferer.sourceLocationFromTitle` iterates `for idx in 0 ..< (lines.count - 1)` (Normalization.swift:565). When `lines` is empty, `lines.count - 1 == -1` and `0 ..< -1` traps at runtime (Range requires lowerBound <= upperBound). The live extraction path guarantees non-empty description (ExtractionEngine.extract rejects empty capture text), so the realistic trigger is narrow, but this is a static helper reachable with any input. Fix: guard `lines.count > 1` (or iterate `lines.indices.dropLast()`) before the loop.
<!-- SECTION:DESCRIPTION:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
LocationInferer.sourceLocationFromTitle now iterates lines.indices.dropLast() instead of 0..<(lines.count-1), which trapped on an empty `lines` (count-1 == -1 → invalid Range). dropLast() yields an empty range for 0 or 1 lines. Test testSourceLocationFromTitle_emptyDescriptionDoesNotTrap covers empty, nil, and whitespace-only descriptions.
<!-- SECTION:FINAL_SUMMARY:END -->
