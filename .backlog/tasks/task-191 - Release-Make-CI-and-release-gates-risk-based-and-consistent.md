---
id: TASK-191
title: 'Release: Make CI and release gates risk-based and consistent'
status: To Do
assignee: []
created_date: '2026-06-11 23:42'
labels:
  - audit
  - release
  - ci
  - tests
dependencies: []
references:
  - .github/workflows/swift-build.yml
  - .github/workflows/release-dmg.yml
  - .github/workflows/release-mas.yml
  - Project.swift
  - README.md
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Normal CI runs the documented fast Swift gate, while tag release workflows run full scheme tests that still exclude AppUITests and LLMEval by scheme design and omit extension tests. Define required PR, pre-release, and release gates explicitly so release confidence is intentional instead of an accidental property of scheme membership.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 PR, pre-release, and tag-release test gates are documented with rationale for included and excluded suites.
- [ ] #2 Extension tests are included in the appropriate gate after TASK-182 or equivalent work lands.
- [ ] #3 Release workflows run the intended gate explicitly rather than relying on ambiguous scheme defaults.
<!-- AC:END -->
