---
id: TASK-423
title: 'Fixture output: Guard against accidental writes to non-fixture stores'
status: To Do
assignee: []
created_date: '2026-06-13 04:21'
labels:
  - audit
  - fixtures
  - data-safety
dependencies: []
references:
  - app/JobhuntApp.swift
  - core/Demo/FixtureSeeder.swift
  - scripts/build-fixture-db.sh
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`--seed-fixture-output` accepts an arbitrary filesystem path and opens it using the test container path. Although the normal build script points at the repo fixture location, the app-level argument can be invoked directly with a production or unrelated store path. `FixtureSeeder.seed` also defaults to `skipIfPopulated`, which can silently exit with stale data if the chosen output already contains jobs.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Fixture-output mode refuses to write to production/default store locations unless an explicit, documented override is provided.
- [ ] #2 Fixture-output mode either requires a new/empty target or uses an explicit overwrite flag with clear failure behavior.
- [ ] #3 Fixture seeding for fixture-output mode does not silently succeed when existing data would make the generated fixture stale or incomplete.
- [ ] #4 The build script and documentation describe the allowed fixture output location and overwrite behavior.
- [ ] #5 Add focused coverage for rejecting an unsafe output path and for failing clearly when the output target is unexpectedly populated.
<!-- AC:END -->
