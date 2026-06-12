---
id: TASK-228
title: >-
  Supply chain: Stop masking Tuist dependency install failures in release
  workflows
status: To Do
assignee: []
created_date: '2026-06-12 01:42'
labels:
  - supply-chain
  - ci
  - release
dependencies: []
references:
  - .github/workflows/release-dmg.yml
  - .github/workflows/release-mas.yml
  - Tuist.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Release workflows currently run `tuist install || true`, allowing dependency resolution failures to be ignored while release builds continue. Make dependency installation deterministic and fail-fast, or remove the step if no Tuist dependencies are required.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Release-DMG and Release-MAS workflows no longer mask `tuist install` failures.
- [ ] #2 If Tuist dependencies are unused, the install step is removed and documented.
- [ ] #3 If Tuist dependencies are required, CI fails before project generation when installation fails.
- [ ] #4 A short release note or contributor doc explains the expected Tuist dependency workflow.
<!-- AC:END -->
