---
id: TASK-272
title: 'LLM: Record fit-scoring prompt and response telemetry'
status: Done
assignee: []
created_date: '2026-06-12 03:26'
updated_date: '2026-06-12 03:30'
labels:
  - audit
  - llm
  - diagnostics
  - fit-scoring
dependencies: []
references:
  - core/Models/LLMRequestAttempt.swift
  - core/LLM/QueueActor.swift
  - core/LLM/ExtractionEngine.swift
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
LLMRequestAttempt supports response format, prompt chars, response chars, preview, and base URL, but fit scoring success records only status/model/duration. Capture comparable telemetry for fit attempts so provider/model regressions are diagnosable.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Fit scoring attempts record prompt character count and response character count.
- [ ] #2 Fit scoring attempts record response format when available.
- [ ] #3 Tests or diagnostics views verify extraction and fit attempts expose comparable telemetry.
<!-- AC:END -->
