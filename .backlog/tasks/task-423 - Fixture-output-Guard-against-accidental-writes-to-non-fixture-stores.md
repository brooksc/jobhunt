---
id: TASK-423
title: 'Fixture output: Guard against accidental writes to non-fixture stores'
status: Done
assignee: []
created_date: '2026-06-13 04:21'
updated_date: '2026-06-15 06:39'
labels:
  - audit
  - fixtures
  - data-safety
dependencies: []
references:
  - app/JobhuntApp.swift
  - core/Demo/FixtureSeeder.swift
  - scripts/build-fixture-db.sh
modified_files:
  - core/App/LaunchPolicy.swift
  - app/JobhuntApp.swift
  - tests/CoreTests/LaunchPolicyTests.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`--seed-fixture-output` accepts an arbitrary filesystem path and opens it using the test container path. Although the normal build script points at the repo fixture location, the app-level argument can be invoked directly with a production or unrelated store path. `FixtureSeeder.seed` also defaults to `skipIfPopulated`, which can silently exit with stale data if the chosen output already contains jobs.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Fixture-output mode refuses to write to production/default store locations unless an explicit, documented override is provided.
- [x] #2 Fixture-output mode either requires a new/empty target or uses an explicit overwrite flag with clear failure behavior.
- [x] #3 Fixture seeding for fixture-output mode does not silently succeed when existing data would make the generated fixture stale or incomplete.
- [x] #4 The build script and documentation describe the allowed fixture output location and overwrite behavior.
- [x] #5 Add focused coverage for rejecting an unsafe output path and for failing clearly when the output target is unexpectedly populated.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Fixture-output mode now refuses a path that resolves to the production store: LaunchPolicy.isSafeFixtureOutputPath compares standardized paths and JobhuntApp throws FixtureOutputError.refusedProductionPath (shown via StoreRecoveryView) (AC#1/#2). It also fails clearly (exit 1 + stderr) if the output target already contains jobs instead of silently no-opping, and uses skipIfPopulated:false so generation always writes fresh (AC#3). build-fixture-db.sh rm's the target first and the fixtures README documents the canonical output location (AC#4). LaunchPolicyTests covers rejecting the production path (incl. normalized ./ form) and allowing other paths (AC#5).
<!-- SECTION:FINAL_SUMMARY:END -->
