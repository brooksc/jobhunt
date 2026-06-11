---
id: TASK-191
title: 'Release: Make CI and release gates risk-based and consistent'
status: Done
assignee: []
created_date: '2026-06-11 23:42'
updated_date: '2026-06-11 23:55'
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
- [x] #1 PR, pre-release, and tag-release test gates are documented with rationale for included and excluded suites.
- [x] #2 Extension tests are included in the appropriate gate after TASK-182 or equivalent work lands.
- [x] #3 Release workflows run the intended gate explicitly rather than relying on ambiguous scheme defaults.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added comment block to all three workflows documenting included/excluded test suites with rationale. Made release-dmg.yml and release-mas.yml use explicit `-only-testing` flags (CoreTests+ServerTests+MCPTests for DMG; CoreTests+ServerTests for MAS) instead of relying on scheme defaults. Added `Run extension Node tests` step to release-dmg.yml — extension tests now run in both the PR gate (swift-build.yml) and the DMG release gate.
<!-- SECTION:FINAL_SUMMARY:END -->
