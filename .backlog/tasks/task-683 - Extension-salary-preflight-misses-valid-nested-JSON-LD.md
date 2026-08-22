---
id: TASK-683
title: Extension salary preflight misses valid nested JSON-LD
status: Done
assignee: []
created_date: '2026-08-21 20:26'
updated_date: '2026-08-22 03:43'
labels:
  - bug
  - extension
  - salary
  - structured-data
dependencies: []
references:
  - extension/capture.js
  - extension/tests/test_preflight_salary.js
modified_files:
  - extension/capture.js
  - extension/tests/test_preflight_salary.js
priority: medium
type: bug
ordinal: 57000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Regression found during the 2026-08-21 code review. Salary preflight recognizes only a top-level object whose type is exactly the string JobPosting. Valid schema.org payloads nested under @graph, rooted in an array, or using an array-valued @type are retained by capture but reported as missing even though baseSalary is present.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Salary preflight finds baseSalary in a top-level JobPosting object
- [ ] #2 Salary preflight finds JobPosting objects nested under @graph
- [ ] #3 Salary preflight handles JSON-LD whose parsed root is an array
- [ ] #4 Salary preflight recognizes array-valued @type containing JobPosting
- [ ] #5 Existing text-first salary precedence remains unchanged
- [ ] #6 Regression tests cover every supported JSON-LD shape
<!-- AC:END -->
