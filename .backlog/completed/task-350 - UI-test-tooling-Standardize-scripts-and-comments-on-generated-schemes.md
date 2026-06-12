---
id: TASK-350
title: 'UI test tooling: Standardize scripts and comments on generated schemes'
status: Done
assignee: []
created_date: '2026-06-12 20:40'
updated_date: '2026-06-12 20:58'
labels:
  - audit
  - tests
  - scripts
  - ui-tests
dependencies: []
references:
  - scripts/screenshot-tests.sh
  - tests/AppUITests/AppUITests.swift
  - Project.swift
  - README.md
  - CONTRIBUTING.md
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
UI helper documentation and scripts reference drifting schemes such as AppUITests and Jobhunt, while Project.swift defines Jobhunt-DMG and Jobhunt-MAS schemes. Manual UI/screenshot lanes may fail before running tests.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 UI test scripts use the generated Jobhunt-DMG scheme unless a dedicated AppUITests scheme is intentionally added.
- [ ] #2 Inline comments and docs show commands that match the current Tuist project.
- [ ] #3 A lightweight script check or manual validation confirms the screenshot/UI commands start xcodebuild successfully.
<!-- AC:END -->
