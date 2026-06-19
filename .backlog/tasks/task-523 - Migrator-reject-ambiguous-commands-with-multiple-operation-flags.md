---
id: TASK-523
title: 'Migrator: reject ambiguous commands with multiple operation flags'
status: To Do
assignee: []
created_date: '2026-06-19 03:56'
labels:
  - audit
  - persistence
  - migrator
  - safety
dependencies: []
references:
  - tools/migrator/Args.swift
  - tools/migrator/main.swift
  - tools/migrator/README.md
  - tests/CoreTests/MigratorTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: `parseArgs()` allows multiple migrator mode flags in one invocation and silently returns the first matching mode in a fixed priority order. For example, a command containing both `--reclean` and `--repair-duplicate-job-numbers` would run whichever branch appears first in `parseArgs`, not necessarily the operator's intended operation.

Why this matters: most migrator modes mutate the live SwiftData store out of band while the app is quit. Silent mode precedence turns a command typo or pasted composite command into an unintended data operation, which is exactly the kind of operator error the migrator should fail closed against.

Suggested implementation: count selected operation flags during argument parsing and reject anything other than exactly one operation mode, except for the default migrate mode where `--output` without another mode remains valid. Update usage text and add focused parser tests or CLI tests for single-mode success and multi-mode rejection.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Supplying two or more operation flags causes `parseArgs()` to return nil and prints a clear error.
- [ ] #2 Single-mode commands such as `--reclean`, `--verify`, and `--repair-duplicate-job-numbers` still parse as before.
- [ ] #3 Default migration using `--output <path>` with no operation flag still works.
- [ ] #4 Usage text communicates that migrator operations are mutually exclusive.
- [ ] #5 Focused tests cover multi-mode rejection and representative valid modes.
<!-- AC:END -->
