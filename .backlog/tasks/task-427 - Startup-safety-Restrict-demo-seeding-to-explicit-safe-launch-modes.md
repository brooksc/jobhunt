---
id: TASK-427
title: 'Startup safety: Restrict demo seeding to explicit safe launch modes'
status: Done
assignee: []
created_date: '2026-06-13 04:33'
updated_date: '2026-06-15 06:15'
labels:
  - audit
  - startup
  - data-safety
dependencies: []
references:
  - app/JobhuntApp.swift
  - tests/AppUITests/AppUITests.swift
modified_files:
  - core/App/LaunchPolicy.swift
  - app/JobhuntApp.swift
  - tests/CoreTests/LaunchPolicyTests.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`--seed-demo-data` is checked independently from `--ui-test-store`. If the argument is passed without a test/fixture mode, the app seeds whichever container was selected, including the production store. A test-only argument should not be able to mutate user data by accident.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Demo seeding is allowed only in explicit safe modes such as UI-test or a documented development/demo store mode.
- [x] #2 Passing `--seed-demo-data` with production store selection fails clearly or is ignored with an explicit diagnostic, according to the chosen policy.
- [x] #3 UI tests that currently rely on `--ui-test-store --seed-demo-data` continue to receive seeded data.
- [ ] #4 Documentation or test helpers describe the supported seeding modes.
- [x] #5 Add focused coverage for rejecting or safely handling `--seed-demo-data` without `--ui-test-store`.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
--seed-demo-data was checked independently of --ui-test-store, so a normal/production launch with that flag would seed DemoSeeder data into the real selected store. Extracted the decision into a pure JobhuntCore LaunchPolicy.allowsDemoSeed(isUITest:seedRequested:) (= seedRequested && isUITest) and gated JobhuntApp's seeding on it (AC#1). A seed flag without --ui-test-store is now ignored with a clear stderr diagnostic rather than mutating user data (AC#2, ignore-with-diagnostic policy). UI tests passing --ui-test-store --seed-demo-data still seed (AC#3). Added LaunchPolicyTests covering allow (UI-test+flag) and the dangerous reject case (flag without UI-test) plus flag-absent (AC#5). AC#4 (document supported seeding modes): the CLAUDE.md AppUITests section already documents --seed-demo-data paired with --ui-test-store; the LaunchPolicy doc comment states the safe-mode rule. LaunchPolicy is the seam the broader TASK-426 LaunchMode work can build on.
<!-- SECTION:FINAL_SUMMARY:END -->
