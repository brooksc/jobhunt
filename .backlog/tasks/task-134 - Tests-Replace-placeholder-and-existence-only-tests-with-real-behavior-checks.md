---
id: TASK-134
title: 'Tests: Replace placeholder and existence-only tests with real behavior checks'
status: Done
assignee: []
created_date: '2026-06-11 03:26'
updated_date: '2026-06-11 20:33'
labels:
  - tests
  - cleanup
  - coverage
dependencies: []
references:
  - tests/CoreTests/CoreTests.swift
  - tests/ServerTests/ServerTests.swift
  - tests/CoreTests/LLMProviderTests.swift
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Some test files contain placeholder or existence-only assertions that inflate suite size without protecting behavior. Replace or remove them so test count reflects meaningful coverage.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 CoreTests placeholder assertion is removed or replaced with a meaningful core contract test.
- [ ] #2 ServerTests enum-access smoke test is removed or replaced with a real server error/response behavior test.
- [ ] #3 Foundation Models availability coverage asserts a concrete supported behavior or is documented as platform smoke coverage only.
- [ ] #4 No test remains whose only assertion is equivalent to proving code compiles.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Replaced three placeholder/existence-only tests:
- CoreTests.swift: replaced `testPlaceholder()` with `CoreEnumRawValueTests` — pins persistence-critical raw string values for JobStatus, ExtractionStatus, LLMRequestStatus, and SiteState. A rename now becomes a test failure.
- ServerTests.swift: replaced enum-access smoke test with `testServerErrorCasesAreDistinct()` — asserts both cases have non-empty localizedDescription and that they differ.
- LLMProviderTests.swift: removed `testIsAvailableReturnsBool()` (Bool is never nil; assertion always passes) and documented `testCompleteThrowsOnOlderOS()` as platform smoke coverage.
All CoreTests and ServerTests pass.
<!-- SECTION:FINAL_SUMMARY:END -->
