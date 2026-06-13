---
id: TASK-427
title: 'Startup safety: Restrict demo seeding to explicit safe launch modes'
status: To Do
assignee: []
created_date: '2026-06-13 04:33'
labels:
  - audit
  - startup
  - data-safety
dependencies: []
references:
  - app/JobhuntApp.swift
  - tests/AppUITests/AppUITests.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`--seed-demo-data` is checked independently from `--ui-test-store`. If the argument is passed without a test/fixture mode, the app seeds whichever container was selected, including the production store. A test-only argument should not be able to mutate user data by accident.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Demo seeding is allowed only in explicit safe modes such as UI-test or a documented development/demo store mode.
- [ ] #2 Passing `--seed-demo-data` with production store selection fails clearly or is ignored with an explicit diagnostic, according to the chosen policy.
- [ ] #3 UI tests that currently rely on `--ui-test-store --seed-demo-data` continue to receive seeded data.
- [ ] #4 Documentation or test helpers describe the supported seeding modes.
- [ ] #5 Add focused coverage for rejecting or safely handling `--seed-demo-data` without `--ui-test-store`.
<!-- AC:END -->
