---
id: TASK-376
title: 'CSV export: Apply formula-injection sanitization to every string field'
status: To Do
assignee: []
created_date: '2026-06-12 22:44'
labels:
  - audit
  - export
  - security
  - csv
dependencies: []
references:
  - core/Services/ExportService.swift
  - tests/CoreTests/JobServiceTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ExportService sanitizes formula-prefixed values for some fields, but application_url, extraction_model, and salary_currency are exported raw even though they can be user-, provider-, or LLM-controlled.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 All string fields in CSV export pass through the same formula-injection sanitizer before escaping.
- [ ] #2 Tests cover formula-trigger prefixes in application_url, extraction_model, salary_currency, and existing sanitized fields.
- [ ] #3 Column order and RFC-4180 escaping remain unchanged.
<!-- AC:END -->
