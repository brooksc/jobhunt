---
id: TASK-107
title: Split migrator internals by command responsibility
status: To Do
assignee: []
created_date: '2026-06-10 20:49'
labels:
  - architecture
  - audit
  - migrator
  - refactor
dependencies: []
references:
  - Project.swift
  - tools/migrator/main.swift
  - tests/CoreTests/MigratorTests.swift
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Architecture audit finding: `JobhuntMigrator` is correctly isolated as a separate target, but its implementation combines argument parsing, SQLite access, mapping, verification, patching, fit-score repair, and reporting in one large `main.swift`. Split internals by command responsibility so migration changes can be reviewed and tested safely without affecting runtime app architecture.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Migrator argument parsing, SQLite reading, migration mapping, verification, patching, and fit-score repair are separated into coherent files or types.
- [ ] #2 Existing CLI modes keep their current behavior and output contract unless an intentional change is documented.
- [ ] #3 Migrator tests cover the extracted responsibilities touched by the refactor.
- [ ] #4 `JobhuntMigrator` builds and existing migrator-related tests pass after the split.
<!-- AC:END -->
