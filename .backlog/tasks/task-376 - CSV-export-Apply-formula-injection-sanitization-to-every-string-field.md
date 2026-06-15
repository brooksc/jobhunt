---
id: TASK-376
title: 'CSV export: Apply formula-injection sanitization to every string field'
status: Done
assignee: []
created_date: '2026-06-12 22:44'
updated_date: '2026-06-15 06:53'
labels:
  - audit
  - export
  - security
  - csv
dependencies: []
references:
  - core/Services/ExportService.swift
  - tests/CoreTests/JobServiceTests.swift
modified_files:
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
- [x] #1 All string fields in CSV export pass through the same formula-injection sanitizer before escaping.
- [x] #2 Tests cover formula-trigger prefixes in application_url, extraction_model, salary_currency, and existing sanitized fields.
- [x] #3 Column order and RFC-4180 escaping remain unchanged.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Moved formula-injection sanitization to a single point — the per-column map now does escapeCsv(sanitizeCsvCell(...)) for EVERY field — so all string columns are covered, including application_url/extraction_model/salary_currency which were exported raw (AC#1). Removed the now-redundant per-field sanitizeCsvCell calls; the sanitizer is idempotent so no double-prefixing, and numeric/date/enum columns never start with a trigger so they're unaffected. Column order and RFC-4180 escaping unchanged (escapeCsv still runs over the same `columns` order) (AC#3). Test testCsvExport_previouslyRawFields_areSanitized covers formula triggers in the three previously-raw fields (AC#2).
<!-- SECTION:FINAL_SUMMARY:END -->
