---
id: TASK-475
title: 'Normalization: Guard sourceLocationFromTitle against empty lines range trap'
status: To Do
assignee: []
created_date: '2026-06-15 03:39'
labels:
  - bug
  - core
  - llm
dependencies: []
references:
  - core/LLM/Normalization.swift
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`LocationInferer.sourceLocationFromTitle` iterates `for idx in 0 ..< (lines.count - 1)` (Normalization.swift:565). When `lines` is empty, `lines.count - 1 == -1` and `0 ..< -1` traps at runtime (Range requires lowerBound <= upperBound). The live extraction path guarantees non-empty description (ExtractionEngine.extract rejects empty capture text), so the realistic trigger is narrow, but this is a static helper reachable with any input. Fix: guard `lines.count > 1` (or iterate `lines.indices.dropLast()`) before the loop.
<!-- SECTION:DESCRIPTION:END -->
