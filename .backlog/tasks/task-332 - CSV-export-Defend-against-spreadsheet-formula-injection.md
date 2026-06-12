---
id: TASK-332
title: 'CSV export: Defend against spreadsheet formula injection'
status: Done
assignee: []
created_date: '2026-06-12 20:06'
updated_date: '2026-06-12 20:50'
labels:
  - audit
  - export
  - csv
  - security
dependencies: []
references:
  - core/Services/ExportService.swift
  - tests/CoreTests/JobServiceTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ExportService.escapeCsv handles CSV quoting but does not neutralize formula-like cell values beginning with characters such as =, +, -, @, or tab. Exported fields include web and LLM-derived text, so opening the CSV in spreadsheet software can execute formulas or external references.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 CSV export neutralizes spreadsheet formula injection for untrusted text fields while preserving readable values.
- [x] #2 Tests cover formula-leading company/title/location/source values and normal CSV quoting behavior.
- [x] #3 The chosen escaping policy is documented or encoded in tests so future column additions apply it consistently.
<!-- AC:END -->
