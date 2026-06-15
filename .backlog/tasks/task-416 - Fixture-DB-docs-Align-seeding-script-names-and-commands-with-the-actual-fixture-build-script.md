---
id: TASK-416
title: >-
  Fixture DB docs: Align seeding script names and commands with the actual
  fixture build script
status: Done
assignee: []
created_date: '2026-06-13 03:22'
updated_date: '2026-06-15 18:43'
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
modified_files:
  - docs/test-db-spec.md
  - scripts/build-fixture-db.sh
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The fixture database spec tells contributors to run `scripts/seed-test-db.sh`, but the working script is `scripts/build-fixture-db.sh`. Align the docs, script names, and comments so the fixture workflow can be followed from a clean checkout.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Fixture DB documentation references the actual script name and supported flags.
- [x] #2 Script header comments and docs use one canonical fixture-generation command.
- [x] #3 Any stale references to `seed-test-db.sh` are removed or replaced with a real compatibility wrapper.
- [x] #4 A dry-run or preflight mode validates the documented command path without mutating committed fixtures.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
docs/test-db-spec.md referenced a nonexistent scripts/seed-test-db.sh, the wrong --seed-fixture flag, and an ungenerated jobhunt-test-manifest.json. Replaced all with the real scripts/build-fixture-db.sh (with --rebuild/--dry-run flags), --seed-fixture-output <path>, and jobhunt-test.manifest.json — so the fixture workflow is followable from a clean checkout (AC#1/#2/#3). Added a --dry-run flag to build-fixture-db.sh that runs the preflight and prints what it would build/seed without building, seeding, or mutating the committed fixture/manifest (AC#4). tests/fixtures/README.md already used the canonical script name. Verified --dry-run works.
<!-- SECTION:FINAL_SUMMARY:END -->
