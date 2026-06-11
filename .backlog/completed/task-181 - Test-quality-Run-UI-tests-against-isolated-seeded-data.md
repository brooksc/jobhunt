---
id: TASK-181
title: 'Test quality: Run UI tests against isolated seeded data'
status: Done
assignee: []
created_date: '2026-06-11 22:16'
updated_date: '2026-06-11 22:36'
labels:
  - audit
  - tests
  - ui-tests
  - data-isolation
dependencies: []
references:
  - tests/AppUITests/AppUITests.swift
  - tests/AppUITests/ScreenshotTests.swift
  - scripts/screenshot-tests.sh
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Current AppUITests launch the real app without an isolated store or deterministic fixture setup, and screenshot tests continue when expected rows are absent. The screenshot helper backs up the production Jobhunt database, confirming tests can interact with user data. Add a UI-test launch mode with an isolated store path and seeded fixtures, then fail when required fixture rows/screens are missing.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 AppUITests run with an isolated test store and cannot read or mutate the user's production database.
- [ ] #2 UI tests seed deterministic jobs, sites, resumes, queue items, and settings needed by the suite.
- [ ] #3 Screenshot/detail tests fail when required seeded rows are missing instead of silently capturing empty states.
<!-- AC:END -->
