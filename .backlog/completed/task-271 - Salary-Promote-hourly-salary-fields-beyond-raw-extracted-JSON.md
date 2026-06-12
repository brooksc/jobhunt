---
id: TASK-271
title: 'Salary: Promote hourly salary fields beyond raw extracted JSON'
status: Done
assignee: []
created_date: '2026-06-12 03:26'
updated_date: '2026-06-12 03:30'
labels:
  - audit
  - salary
  - llm
  - data-model
dependencies: []
references:
  - core/LLM/PromptBuilder.swift
  - core/LLM/Normalization.swift
  - core/LLM/ExtractionEngine.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The prompt asks for salary_hourly_min and salary_hourly_max and normalization computes them, but ExtractionResult and typed persistence only expose annual salary values. Add typed hourly fields or a documented projection so UI/export/query code can inspect original hourly pay without parsing raw JSON.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Hourly min/max values are available through a typed model/projection or documented accessor.
- [ ] #2 Exports and relevant UI can display hourly pay separately from annualized salary where appropriate.
- [ ] #3 Tests cover hourly extraction preserving both raw hourly and annualized values.
<!-- AC:END -->
