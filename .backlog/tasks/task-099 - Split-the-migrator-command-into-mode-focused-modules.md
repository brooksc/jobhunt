---
id: TASK-099
title: Split the migrator command into mode-focused modules
status: To Do
assignee: []
created_date: '2026-06-10 07:49'
labels:
  - audit
  - refactor
  - migrator
dependencies: []
references:
  - tools/migrator/main.swift
  - tests/CoreTests/MigratorTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Audit finding: `tools/migrator/main.swift` is a 1,378-line command that combines argument parsing, SQLite helpers, migration, verification, patching, fit-score repair, and reporting. Split it into mode-focused files so future migration changes can be tested and reviewed without understanding the entire command at once.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Argument parsing, SQLite access helpers, migration, verification, patching, and fit-score repair are separated into coherent files or types.
- [ ] #2 Existing migrator command modes keep their current CLI behavior and output contract unless an intentional change is documented.
- [ ] #3 Migrator tests cover the extracted units or command modes touched by the split.
- [ ] #4 The migrator target builds and existing CoreTests pass after the refactor.
<!-- AC:END -->
