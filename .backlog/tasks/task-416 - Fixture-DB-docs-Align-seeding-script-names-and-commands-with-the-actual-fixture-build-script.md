---
id: TASK-416
title: >-
  Fixture DB docs: Align seeding script names and commands with the actual
  fixture build script
status: To Do
assignee: []
created_date: '2026-06-13 03:22'
labels:
  - audit
  - repo-hygiene
  - tests
  - docs
  - fixtures
dependencies: []
references:
  - docs/test-db-spec.md
  - scripts/build-fixture-db.sh
  - tests/fixtures
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The fixture database spec tells contributors to run `scripts/seed-test-db.sh`, but the working script is `scripts/build-fixture-db.sh`. Align the docs, script names, and comments so the fixture workflow can be followed from a clean checkout.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Fixture DB documentation references the actual script name and supported flags.
- [ ] #2 Script header comments and docs use one canonical fixture-generation command.
- [ ] #3 Any stale references to `seed-test-db.sh` are removed or replaced with a real compatibility wrapper.
- [ ] #4 A dry-run or preflight mode validates the documented command path without mutating committed fixtures.
<!-- AC:END -->
