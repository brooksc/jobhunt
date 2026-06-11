---
id: TASK-134
title: 'Tests: Replace placeholder and existence-only tests with real behavior checks'
status: To Do
assignee: []
created_date: '2026-06-11 03:26'
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
