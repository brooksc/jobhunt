---
id: TASK-184
title: 'Test quality: Add seeded UI workflow tests for high-risk user journeys'
status: To Do
assignee: []
created_date: '2026-06-11 22:19'
labels:
  - audit
  - tests
  - ui-tests
  - workflow
dependencies: []
references:
  - tests/AppUITests/BehaviorUITests.swift
  - tests/AppUITests/JobsScreenUITests.swift
  - tests/AppUITests/ScreenshotTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Existing AppUITests mostly cover navigation, menu presence, screenshots, and accessibility state. Add a small deterministic workflow suite for high-risk flows found in audits: Add Job, Save Search, archive/delete, resume activation, queue process-selected, and visible error reporting.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Seeded UI tests cover at least Add Job and Save Search success paths.
- [ ] #2 Seeded UI tests cover at least one destructive/status workflow with visible success or failure behavior.
- [ ] #3 Seeded UI tests cover at least one error-reporting path after the app-wide error mechanism is wired.
<!-- AC:END -->
